'use strict';
// App problems module (owner spec F + G, 17 Nov 2026; extended by the "AI Agent + Health System" spec, parts 1-2): what goes wrong for
// real people, from every app (the website, the admin panel and the Vendor, Staff and User Android apps), for the admin's Health and
// App Health pages. Crash stacks of the Android apps also go to Firebase Crashlytics (free); this keeps the counts the admin reads.
//
//   reportAppProblems  anyone -> {app, platform, version, device, os, network, deviceId, problems: [{kind, message, screen, option, ms,
//                                 side, cause, shot?}]} -> {saved, cases: [<caseId>]}
//   reportProblem      anyone -> {app, platform, version, device, deviceId, text, screen, screenshot?} -> {id}   "Report a problem"
//
//   appProblems/<app>~<platform>~<kind>~<fp> {app, platform, kind, message, screen, option, count, users, usersMore, people,
//                                            devices: {<model>: n}, oses: {<version>: n}, side, cause, status, burst, lastAt,
//                                            lastVersion, lastDevice, lastRole, lastUserCode, examples, shots, shotPaths, lastShot}
//     ONE record per problem (owner, 18 Nov 2026: cost cuts part 3): the same problem only counts up. No record per person or per
//     time: `people` holds up to MAX_PEOPLE short codes (a hash of the account or device) to count `users`; past that `usersMore`
//     is true ("100+"). `examples` are the last 3 times it happened (time, version, phone, role, Vendor/Staff ID, phone number...).
//     Screenshots: at most 3 a problem (`shots`, `shotPaths`), in the US bucket (functions/problem-shots.js), never for a slow
//     save or many taps (only counted). Records written before this (appCases, appShots, appProblems/<id>/who) are no longer
//     written; scripts/old-problem-records.cjs counts them and deletes them only with the owner's OK.
//   appProblemsDaily/<day>~<app>~<platform>  {day, app, platform, total, kinds: {<kind>: n}}
//   problemReports/<id>                      {app, platform, version, device, text, screen, screenshotPath, uid, role, userCode, status, at}
//                                            screenshotPath is reports/<id>.<jpg|png> in the US bucket
//   appProblemDevices/<device hash>~<day>    {count, reports, shots}   the per-device daily cap (functions only)
//   healthAlerts/<problemId>                 the burst alert (alerts.js); settings/health {burstCount, burstMinutes, burstSides}
//   billingAlert (Pub/Sub "billing-alerts")  a Google Cloud budget passed a new threshold: red line + admin push (billing.js)
//   solvedProblems/<id> {problemId, by, at}  written when the admin marks a problem solved or its fix goes live: the problem becomes
//                                            'solved', its alert closes and its screenshots are deleted (problemSolved trigger); the
//                                            bucket deletes any screenshot after 30 days by itself
//
// Cost guards: a device sends at most DEVICE_DAILY_CAP problems, SHOTS_PER_DAY screenshots and REPORTS_PER_DAY reports a day (the rest
// are dropped), at most MAX_BATCH problems a call, texts are cut short, emails / links / long numbers are taken out, bots are ignored,
// a screenshot is at most 80 KB (the phone makes it 30-60 KB) and a problem keeps at most 3.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onMessagePublished} = require('firebase-functions/v2/pubsub');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {shots: shotStore} = require('../../problem-shots');
const {createHash} = require('node:crypto');
const {task} = require('../../task');
const {healthConfig, deviceParts, sideOf, nextBurst, SIDES} = require('./cases');
const {raiseBurstAlert} = require('./alerts');
const {onBudgetMessage} = require('./billing');

const APPS = ['customer', 'vendor', 'staff', 'admin'];
// tap: the same option tapped again and again with no answer; freeze: the app hung; stuck: a screen kept loading; repeat: the same save
// or upload failed again (owner spec part 2).
const KINDS = ['crash', 'error', 'login', 'otp', 'email', 'location', 'upload', 'api', 'slow', 'tap', 'freeze', 'stuck', 'repeat'];
const DEVICE_DAILY_CAP = 30;
const SHOTS_PER_DAY = 10;
const REPORTS_PER_DAY = 5;
const MAX_BATCH = 10;
// Counted only, never a screenshot (owner, 18 Nov 2026): a slow save and many taps are guesses, not failures the person saw.
const NO_SHOT_KINDS = ['slow', 'tap'];
const MAX_PEOPLE = 100;
const MAX_EXAMPLES = 3;
const BOT = /bot|crawl|spider|slurp|headless|lighthouse|phantom|puppeteer|playwright|selenium|curl|wget|python-requests/i;
const options = {region: 'us-central1', maxInstances: 3, invoker: 'public'};

const dayKey = (now = Date.now()) => new Date(now + 19800000).toISOString().slice(0, 10);
const hash = value => createHash('sha256').update(String(value)).digest('hex');
const clip = (value, max) => String(value ?? '').trim().replace(/\s+/g, ' ').slice(0, max);
/// No emails, links or long numbers (phone numbers) in anything kept.
const clean = (value, max) => clip(value, 2000)
  .replace(/\S+@\S+/g, '<email>').replace(/https?:\/\/\S+/g, '<link>').replace(/\d{6,}/g, '<number>').slice(0, max);

/// The same id on every device for one problem: the app, the kind and the cleaned message.
const fingerprint = (app, kind, message) => hash(`${app}|${kind}|${message}`).slice(0, 16);
/// The document of one problem: the website and the User Android app are one app ('customer') on two platforms, kept apart.
const problemId = (app, platform, kind, message) => `${app}~${platform}~${kind}~${fingerprint(app, kind, message)}`;

/// The checked header of a call: which app, its version, the device, its Android version and network ('' when not sent).
function header(data = {}) {
  const app = APPS.includes(data.app) ? data.app : null;
  if (!app) throw new HttpsError('invalid-argument', `app must be one of ${APPS.join(', ')}`);
  return {
    app,
    platform: data.platform === 'android' ? 'android' : 'web',
    version: clip(data.version, 30),
    device: clean(data.device, 80),
    deviceId: clip(data.deviceId, 100),
    os: clip(data.os, 30),
    network: clip(data.network, 20),
  };
}

/// Who the signed-in person is for the admin: their Vendor / Staff ID and phone ('' for visitors and when not on file).
async function contactOf(db, auth) {
  if (!auth?.uid) return {code: '', phone: ''};
  const role = auth.token?.role;
  const phone = d => clip(d?.phone || d?.mobile || d?.whatsapp || '', 20);
  try {
    if (role === 'vendor' || role === 'provider') {
      const d = (await db.collection(role === 'provider' ? 'serviceProviders' : 'vendors').doc(auth.uid).get()).data();
      return {code: String(d?.vendorCode || d?.providerCode || ''), phone: phone(d)};
    }
    if (role === 'staff') {
      const d = (await db.collection('fieldStaff').doc(auth.uid).get()).data();
      return {code: String(d?.staffCode || d?.code || ''), phone: phone(d)};
    }
    return {code: '', phone: phone((await db.collection('users').doc(auth.uid).get()).data())};
  } catch {
    return {code: '', phone: ''}; // only labels
  }
}

/// The Vendor / Staff ID of the signed-in person ('' for customers and visitors).
const userCode = async (db, auth) => (await contactOf(db, auth)).code;

/// Takes [n] of the device's daily allowance ([field] 'count', 'shots' or 'reports'); returns how many may be kept.
async function takeAllowance(db, deviceKey, n, field, cap, now) {
  const ref = db.collection('appProblemDevices').doc(`${deviceKey}~${dayKey(now)}`);
  return db.runTransaction(async tx => {
    const used = (await tx.get(ref)).data()?.[field] ?? 0;
    const allowed = Math.max(0, Math.min(n, cap - used));
    if (allowed > 0) tx.set(ref, {[field]: used + allowed, day: dayKey(now), expiresAt: Timestamp.fromMillis(now + 3 * 86400000)}, {merge: true});
    return allowed;
  });
}

const deviceKeyOf = (h, request) => hash(h.deviceId || request.rawRequest?.ip || 'unknown').slice(0, 24);
const isBot = request => BOT.test(String(request.rawRequest?.headers?.['user-agent'] || ''));

/// An automatic screenshot (a small JPEG) as bytes, or null when there is none or it is not a JPEG / too big (then it is left out).
function autoShotOf(base64) {
  const shot = shotStore.shotBytes(base64);
  return shot?.type === 'image/jpeg' ? shot : null;
}

/// One problem from a call, checked.
function problemOf(p) {
  return {
    kind: KINDS.includes(p?.kind) ? p.kind : 'error',
    message: clean(p?.message, 300),
    screen: clip(p?.screen, 60),
    option: clean(p?.option, 80),
    ms: Number.isFinite(Number(p?.ms)) ? Math.round(Number(p.ms)) : null,
    side: SIDES.includes(p?.side) ? p.side : 'our',
    cause: clip(p?.cause, 40).replace(/[^a-z_]/g, ''),
    shot: NO_SHOT_KINDS.includes(p?.kind) ? null : autoShotOf(p?.shot),
  };
}

let configCache = {at: -Infinity, value: null};
/// settings/health, read at most every 5 minutes.
async function loadConfig(db, now) {
  if (now - configCache.at < 300000 && configCache.value) return configCache.value;
  let d = {};
  try {
    d = (await db.collection('settings').doc('health').get()).data() || {};
  } catch { /* defaults */ }
  configCache = {at: now, value: healthConfig(d)};
  return configCache.value;
}
const resetConfig = () => { configCache = {at: -Infinity, value: null}; };

/// Saves a batch of problems: each problem's one record counts up (the tests call it with a fake request, a fake [send] for the admin
/// push and a fake [bucket]).
async function saveProblems(db, request, now = Date.now(), {send, bucket} = {}) {
  if (isBot(request)) return {saved: 0, problems: []};
  const data = request.data || {};
  const h = header(data);
  const list = (Array.isArray(data.problems) ? data.problems : []).slice(0, MAX_BATCH).map(problemOf).filter(p => p.message);
  if (!list.length) return {saved: 0, problems: []};
  const deviceKey = deviceKeyOf(h, request);
  const allowed = await takeAllowance(db, deviceKey, list.length, 'count', DEVICE_DAILY_CAP, now);
  const keep = list.slice(0, allowed);
  if (!keep.length) return {saved: 0, problems: []};
  const wantShots = keep.filter(p => p.shot).length;
  let shotsLeft = wantShots ? await takeAllowance(db, deviceKey, wantShots, 'shots', SHOTS_PER_DAY, now) : 0;
  const cfg = await loadConfig(db, now);
  const role = String(request.auth?.token?.role || '');
  const {code, phone} = await contactOf(db, request.auth);
  const person = hash(request.auth?.uid ? `u_${request.auth.uid}` : `d_${deviceKey}`).slice(0, 10);
  const {model, os} = deviceParts(h.device, h.os);
  const at = Timestamp.fromMillis(now);
  const kinds = {};
  const alerts = [];
  const uploads = [];
  // The same problem twice in one call is counted once with n = 2.
  const groups = new Map();
  for (const p of keep) {
    const id = problemId(h.app, h.platform, p.kind, p.message);
    const g = groups.get(id) || {id, p, n: 0, shots: []};
    g.n++;
    if (p.shot && shotsLeft > 0) { g.shots.push(p.shot); shotsLeft--; }
    groups.set(id, g);
    kinds[p.kind] = (kinds[p.kind] || 0) + 1;
  }
  for (const g of groups.values()) {
    const ref = db.collection('appProblems').doc(g.id);
    const result = await db.runTransaction(async tx => {
      const prev = (await tx.get(ref)).data() || {};
      // Who had it: a short code per person, at most MAX_PEOPLE (then "100+").
      const people = Array.isArray(prev.people) ? prev.people : [];
      const known = people.includes(person);
      const room = !known && people.length < MAX_PEOPLE;
      const users = (prev.users || 0) + (room ? 1 : 0);
      const usersMore = prev.usersMore === true || (!known && !room);
      const devices = {...(prev.devices || {}), [model]: ((prev.devices || {})[model] || 0) + g.n};
      const oses = {...(prev.oses || {}), [os]: ((prev.oses || {})[os] || 0) + g.n};
      const side = sideOf({clientSide: g.p.side, users, devices, oses});
      const {burst, alert} = nextBurst(prev.burst, g.n, now, cfg);
      // At most 3 screenshots for one problem, all apps and people together.
      const had = Number(prev.shots) || 0;
      const take = g.shots.slice(0, Math.max(0, shotStore.MAX_PER_PROBLEM - had));
      const paths = take.map((_, i) => `${shotStore.problemFolder(g.id)}${now}-${had + i + 1}.jpg`);
      const example = {
        at, version: h.version, device: h.device, model, os, network: h.network, role, userCode: code, phone, screen: g.p.screen,
        option: g.p.option, ...(g.p.ms != null ? {ms: g.p.ms} : {}), shot: paths.at(-1) || '',
      };
      tx.set(ref, {
        app: h.app, platform: h.platform, kind: g.p.kind, message: g.p.message, screen: g.p.screen, option: g.p.option,
        count: FieldValue.increment(g.n), users, usersMore, ...(room ? {people: [...people, person]} : {}),
        devices: {[model]: FieldValue.increment(g.n)}, oses: {[os]: FieldValue.increment(g.n)},
        side, cause: g.p.cause, status: 'open', burst, lastAt: at, lastVersion: h.version, lastDevice: h.device, lastRole: role,
        lastUserCode: code, lastNetwork: h.network, ...(g.p.ms != null ? {lastMs: g.p.ms} : {}),
        examples: [example, ...(Array.isArray(prev.examples) ? prev.examples : [])].slice(0, MAX_EXAMPLES),
        ...(paths.length ? {shots: had + paths.length, shotPaths: [...(prev.shotPaths || []), ...paths], lastShot: paths.at(-1)} : {}),
        ...(prev.status === 'solved' ? {reopenedAt: at} : {}),
      }, {merge: true});
      return {side, burst, alert, paths, take};
    });
    result.take.forEach((shot, i) => uploads.push([result.paths[i], shot]));
    if (result.alert && cfg.burstSides.includes(result.side)) {
      const {shot: _shot, ...problem} = g.p;
      alerts.push({id: g.id, ...problem, app: h.app, platform: h.platform, side: result.side, n: result.burst.n});
    }
  }
  await db.collection('appProblemsDaily').doc(`${dayKey(now)}~${h.app}~${h.platform}`).set({
    day: dayKey(now), app: h.app, platform: h.platform, total: FieldValue.increment(keep.length),
    kinds: Object.fromEntries(Object.entries(kinds).map(([k, n]) => [k, FieldValue.increment(n)])),
  }, {merge: true});
  if (uploads.length) {
    const b = bucket ?? shotStore.shotBucket();
    // A screenshot that cannot be saved is left out; the problem itself is already counted.
    await Promise.all(uploads.map(([path, shot]) => shotStore.saveShot(b, path, shot).catch(error => console.warn('Screenshot not saved', error.message))));
  }
  for (const a of alerts) await raiseBurstAlert(db, a, {n: a.n, minutes: cfg.burstMinutes, now, send});
  return {saved: keep.length, problems: [...groups.keys()], alerts: alerts.length};
}

/// A problem was solved: its record says so, its alert closes and its screenshots are deleted (new ones may come if it happens again).
async function markSolved(db, problemId, now = Date.now(), {bucket} = {}) {
  const ref = db.collection('appProblems').doc(problemId);
  const prev = (await ref.get()).data();
  if (!prev) return 0;
  const at = Timestamp.fromMillis(now);
  await ref.update({
    status: 'solved', solvedAt: at, shots: 0, shotPaths: [], lastShot: '',
    examples: (Array.isArray(prev.examples) ? prev.examples : []).map(e => ({...e, shot: ''})),
  });
  await db.collection('healthAlerts').doc(problemId).set({open: false, closedAt: at}, {merge: true});
  await shotStore.deleteShots(bucket ?? shotStore.shotBucket(), shotStore.problemFolder(problemId));
  return (prev.shotPaths || []).length;
}

/// Deletes the screenshots the version before 18 Nov 2026 left in Firestore (appShots) once they are past their 30 days. New
/// screenshots are in the US bucket, which deletes them after 30 days by itself.
async function cleanShots(db, now = Date.now()) {
  const old = await db.collection('appShots').where('expiresAt', '<', Timestamp.fromMillis(now)).limit(300).get();
  if (old.size) {
    const b = db.batch();
    old.docs.forEach(d => b.delete(d.ref));
    await b.commit();
  }
  return old.size;
}

/// The screenshot as bytes and type, or null; a wrong one is refused.
function screenshotOf(base64) {
  if (!base64) return null;
  const shot = shotStore.shotBytes(base64);
  if (!shot) throw new HttpsError('invalid-argument', `The screenshot must be a PNG or JPEG under ${Math.round(shotStore.MAX_BYTES / 1024)} KB.`);
  return shot;
}

/// Saves one "Report a problem" (the tests pass a fake [bucket]).
async function saveReport(db, bucket, request, now = Date.now()) {
  const data = request.data || {};
  const h = header(data);
  const text = clean(data.text, 1000);
  if (!text) throw new HttpsError('invalid-argument', 'Write what went wrong.');
  const shot = screenshotOf(data.screenshot);
  if (isBot(request)) return {id: ''};
  if (!(await takeAllowance(db, deviceKeyOf(h, request), 1, 'reports', REPORTS_PER_DAY, now))) {
    throw new HttpsError('resource-exhausted', `You have sent ${REPORTS_PER_DAY} reports today. Thank you — we are looking at them.`);
  }
  const ref = db.collection('problemReports').doc();
  let screenshotPath = '';
  if (shot) {
    screenshotPath = await shotStore.saveShot(bucket, `reports/${ref.id}.${shot.ext}`, shot);
  }
  await ref.set({
    app: h.app, platform: h.platform, version: h.version, device: h.device, text, screen: clip(data.screen, 60), screenshotPath,
    uid: request.auth?.uid || '', role: String(request.auth?.token?.role || ''), userCode: await userCode(db, request.auth),
    status: 'new', at: Timestamp.fromMillis(now),
  });
  return {id: ref.id};
}

exports.reportAppProblems = onCall(options, async request => saveProblems(getFirestore(), request));
exports.billingAlert = onMessagePublished({topic: 'billing-alerts', region: 'asia-south1', maxInstances: 1}, async event => {
  const alerted = await onBudgetMessage(getFirestore(), event.data?.message?.json || {});
  if (alerted) console.log('Billing alert sent to the admin');
});
exports.problemSolved = onDocumentCreated({document: 'solvedProblems/{id}', region: 'asia-south1', maxInstances: 2}, async event => {
  const problemId = String(event.data?.data()?.problemId || '');
  if (problemId) console.log('Problem solved, screenshots deleted', await markSolved(getFirestore(), problemId));
});
exports.cleanAppShots = task(async () => console.log('App screenshots deleted', await cleanShots(getFirestore())));
exports.reportProblem = onCall({...options, memory: '256MiB'}, async request => saveReport(getFirestore(), shotStore.shotBucket(), request));

exports._test = {MAX_PEOPLE, MAX_EXAMPLES, NO_SHOT_KINDS, saveProblems, saveReport, header, clean, fingerprint, problemId, screenshotOf, autoShotOf, problemOf, contactOf, cleanShots, markSolved, resetConfig, KINDS, DEVICE_DAILY_CAP, SHOTS_PER_DAY, REPORTS_PER_DAY, dayKey};
