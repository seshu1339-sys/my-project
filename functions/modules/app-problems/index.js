'use strict';
// App problems module (owner spec F + G, 17 Nov 2026; extended by the "AI Agent + Health System" spec, parts 1-2): what goes wrong for
// real people, from every app (the website, the admin panel and the Vendor, Staff and User Android apps), for the admin's Health and
// App Health pages. Crash stacks of the Android apps also go to Firebase Crashlytics (free); this keeps the counts the admin reads.
//
//   reportAppProblems  anyone -> {app, platform, version, device, os, network, deviceId, problems: [{kind, message, screen, option, ms,
//                                 side, cause, shot?}]} -> {saved, cases: [<caseId>]}
//   reportProblem      anyone -> {app, platform, version, device, deviceId, text, screen, screenshot?} -> {id}   "Report a problem"
//
//   appProblems/<app>~<platform>~<kind>~<fp> {app, platform, kind, message, screen, option, count, users, devices: {<model>: n},
//                                            oses: {<version>: n}, side, cause, status, burst, lastAt, lastVersion, lastDevice,
//                                            lastRole, lastUserCode, lastShot}
//   appProblems/<id>/who/<person>            one per person (signed-in account, else device): how `users` is counted
//   appCases/<id>                            every case: app, platform, version, screen, option, device, os, network, uid, phone,
//                                            userCode, role, what, side, cause, problemId, at, shot (functions only, admin reads)
//   appShots/<caseId>                        {problemId, data (JPEG, base64), at, expiresAt}: the automatic screenshot, deleted when the
//                                            problem is solved or after 30 days (cleanAppShots task)
//   appProblemsDaily/<day>~<app>~<platform>  {day, app, platform, total, kinds: {<kind>: n}}
//   problemReports/<id>                      {app, platform, version, device, text, screen, screenshotPath, uid, role, userCode, status, at}
//   appProblemDevices/<device hash>~<day>    {count, reports, shots}   the per-device daily cap (functions only)
//   healthAlerts/<problemId>                 the burst alert (alerts.js); settings/health {burstCount, burstMinutes, burstSides}
//   billingAlert (Pub/Sub "billing-alerts")  a Google Cloud budget passed a new threshold: red line + admin push (billing.js)
//   solvedProblems/<id> {problemId, by, at}  written when the admin marks a problem solved or its fix goes live: the problem becomes
//                                            'solved', its alert closes and its screenshots are deleted (problemSolved trigger)
//
// Cost guards: a device sends at most DEVICE_DAILY_CAP problems, SHOTS_PER_DAY screenshots and REPORTS_PER_DAY reports a day (the rest
// are dropped), at most MAX_BATCH problems a call, texts are cut short, emails / links / long numbers are taken out, bots are ignored,
// an automatic screenshot is at most 120 KB and a report's at most 400 KB.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onMessagePublished} = require('firebase-functions/v2/pubsub');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
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
const MAX_SHOT = 120 * 1024;
const SHOT_DAYS = 30;
const REPORTS_PER_DAY = 5;
const MAX_BATCH = 10;
const MAX_SCREENSHOT = 400 * 1024;
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

/// An automatic screenshot (a small JPEG, base64) or null when there is none or it is not a JPEG / too big (then it is just left out).
function autoShotOf(base64) {
  if (typeof base64 !== 'string' || !base64 || base64.length > Math.ceil(MAX_SHOT * 4 / 3) + 8) return null;
  const head = Buffer.from(base64.slice(0, 8), 'base64');
  return head[0] === 0xff && head[1] === 0xd8 ? base64 : null;
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
    shot: autoShotOf(p?.shot),
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

/// Saves a batch of problems, one case record each (the tests call it with a fake request and a fake [send] for the admin push).
async function saveProblems(db, request, now = Date.now(), {send} = {}) {
  if (isBot(request)) return {saved: 0, cases: []};
  const data = request.data || {};
  const h = header(data);
  const list = (Array.isArray(data.problems) ? data.problems : []).slice(0, MAX_BATCH).map(problemOf).filter(p => p.message);
  if (!list.length) return {saved: 0, cases: []};
  const deviceKey = deviceKeyOf(h, request);
  const allowed = await takeAllowance(db, deviceKey, list.length, 'count', DEVICE_DAILY_CAP, now);
  const keep = list.slice(0, allowed);
  if (!keep.length) return {saved: 0, cases: []};
  const wantShots = keep.filter(p => p.shot).length;
  let shotsLeft = wantShots ? await takeAllowance(db, deviceKey, wantShots, 'shots', SHOTS_PER_DAY, now) : 0;
  const cfg = await loadConfig(db, now);
  const role = String(request.auth?.token?.role || '');
  const {code, phone} = await contactOf(db, request.auth);
  const person = request.auth?.uid ? `u_${request.auth.uid}` : `d_${deviceKey}`;
  const {model, os} = deviceParts(h.device, h.os);
  const at = Timestamp.fromMillis(now);
  const batch = db.batch();
  const kinds = {};
  const cases = [];
  const alerts = [];
  // The same problem twice in one call is counted once with n = 2 (the reads below are made before any write).
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
    const whoRef = ref.collection('who').doc(person);
    const [snap, who] = await db.getAll(ref, whoRef);
    const prev = snap.data() || {};
    const users = (prev.users || 0) + (who.exists ? 0 : 1);
    const devices = {...(prev.devices || {}), [model]: ((prev.devices || {})[model] || 0) + g.n};
    const oses = {...(prev.oses || {}), [os]: ((prev.oses || {})[os] || 0) + g.n};
    const side = sideOf({clientSide: g.p.side, users, devices, oses});
    const {burst, alert} = nextBurst(prev.burst, g.n, now, cfg);
    let lastShot = null;
    for (let i = 0; i < g.n; i++) {
      const caseRef = db.collection('appCases').doc();
      const shot = g.shots[i];
      batch.set(caseRef, {
        problemId: g.id, app: h.app, platform: h.platform, version: h.version, kind: g.p.kind, what: g.p.message, screen: g.p.screen,
        option: g.p.option, device: h.device, model, os, network: h.network, uid: request.auth?.uid || '', role, userCode: code, phone,
        side, cause: g.p.cause, ...(g.p.ms != null ? {ms: g.p.ms} : {}), shot: !!shot, at,
      });
      if (shot) {
        batch.set(db.collection('appShots').doc(caseRef.id), {problemId: g.id, data: shot, at, expiresAt: Timestamp.fromMillis(now + SHOT_DAYS * 86400000)});
        lastShot = caseRef.id;
      }
      cases.push(caseRef.id);
    }
    if (!who.exists) batch.set(whoRef, {at});
    batch.set(ref, {
      app: h.app, platform: h.platform, kind: g.p.kind, message: g.p.message, screen: g.p.screen, option: g.p.option,
      count: FieldValue.increment(g.n), users, devices: {[model]: FieldValue.increment(g.n)}, oses: {[os]: FieldValue.increment(g.n)},
      side, cause: g.p.cause, status: 'open', burst, lastAt: at, lastVersion: h.version, lastDevice: h.device, lastRole: role,
      lastUserCode: code, lastNetwork: h.network, ...(g.p.ms != null ? {lastMs: g.p.ms} : {}), ...(lastShot ? {lastShot} : {}),
      ...(prev.status === 'solved' ? {reopenedAt: at} : {}),
    }, {merge: true});
    if (alert && cfg.burstSides.includes(side)) alerts.push({id: g.id, ...g.p, app: h.app, platform: h.platform, side, n: burst.n});
  }
  batch.set(db.collection('appProblemsDaily').doc(`${dayKey(now)}~${h.app}~${h.platform}`), {
    day: dayKey(now), app: h.app, platform: h.platform, total: FieldValue.increment(keep.length),
    kinds: Object.fromEntries(Object.entries(kinds).map(([k, n]) => [k, FieldValue.increment(n)])),
  }, {merge: true});
  await batch.commit();
  for (const a of alerts) await raiseBurstAlert(db, a, {n: a.n, minutes: cfg.burstMinutes, now, send});
  return {saved: keep.length, cases, alerts: alerts.length};
}

/// A problem was solved: its record says so, its alert closes and its screenshots are marked for deletion (cleanShots deletes them).
async function markSolved(db, problemId, now = Date.now()) {
  const ref = db.collection('appProblems').doc(problemId);
  if (!(await ref.get()).exists) return 0;
  const at = Timestamp.fromMillis(now);
  await ref.update({status: 'solved', solvedAt: at});
  await db.collection('healthAlerts').doc(problemId).set({open: false, closedAt: at}, {merge: true});
  const shots = await db.collection('appShots').where('problemId', '==', problemId).limit(400).get();
  const b = db.batch();
  shots.docs.forEach(d => b.delete(d.ref));
  if (shots.size) await b.commit();
  return shots.size;
}

/// Deletes the automatic screenshots that are past their 30 days, and those of solved problems (a few hundred a run).
async function cleanShots(db, now = Date.now()) {
  const old = await db.collection('appShots').where('expiresAt', '<', Timestamp.fromMillis(now)).limit(300).get();
  const solved = await db.collection('appShots').where('solved', '==', true).limit(300).get();
  const refs = [...new Map([...old.docs, ...solved.docs].map(d => [d.id, d.ref])).values()];
  for (let i = 0; i < refs.length; i += 400) {
    const b = db.batch();
    refs.slice(i, i + 400).forEach(r => b.delete(r));
    await b.commit();
  }
  return refs.length;
}

/// The screenshot as bytes and type, or null; a wrong one is refused.
function screenshotOf(base64) {
  if (!base64) return null;
  if (typeof base64 !== 'string' || base64.length > Math.ceil(MAX_SCREENSHOT * 4 / 3) + 8) throw new HttpsError('invalid-argument', 'The screenshot must be under 400 KB.');
  const bytes = Buffer.from(base64, 'base64');
  const png = bytes[0] === 0x89 && bytes[1] === 0x50, jpeg = bytes[0] === 0xff && bytes[1] === 0xd8;
  if (!png && !jpeg) throw new HttpsError('invalid-argument', 'The screenshot must be a PNG or JPEG.');
  return {bytes, type: png ? 'image/png' : 'image/jpeg', ext: png ? 'png' : 'jpg'};
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
    screenshotPath = `problemReports/${ref.id}.${shot.ext}`;
    await bucket.file(screenshotPath).save(shot.bytes, {contentType: shot.type, resumable: false});
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
exports.reportProblem = onCall({...options, memory: '256MiB'}, async request => saveReport(getFirestore(), getStorage().bucket(), request));

exports._test = {saveProblems, saveReport, header, clean, fingerprint, problemId, screenshotOf, autoShotOf, problemOf, contactOf, cleanShots, markSolved, resetConfig, KINDS, DEVICE_DAILY_CAP, SHOTS_PER_DAY, REPORTS_PER_DAY, dayKey};
