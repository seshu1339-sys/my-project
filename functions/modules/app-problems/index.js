'use strict';
// App problems module (owner spec F + G, 17 Nov 2026): what goes wrong for real people, from every app (the website, the admin panel and
// the Vendor, Staff and User Android apps), for the admin's Health and App Health pages. Crash stacks of the Android apps also go to
// Firebase Crashlytics (free); this keeps the counts the admin reads in the panel.
//
//   reportAppProblems  anyone -> {app, platform, version, device, deviceId, problems: [{kind, message, screen, ms}]} -> {saved}
//   reportProblem      anyone -> {app, platform, version, device, deviceId, text, screen, screenshot?} -> {id}   "Report a problem"
//
//   appProblems/<app>~<platform>~<kind>~<fp> {app, platform, kind, message, screen, count, lastAt, lastVersion, lastDevice, lastRole, lastUserCode}
//   appProblemsDaily/<day>~<app>~<platform>  {day, app, platform, total, kinds: {<kind>: n}}
//   problemReports/<id>                      {app, platform, version, device, text, screen, screenshotPath, uid, role, userCode, status, at}
//   appProblemDevices/<device hash>~<day>    {count, reports}   the per-device daily cap (functions only)
//
// Cost guards: a device sends at most DEVICE_DAILY_CAP problems and REPORTS_PER_DAY reports a day (the rest are dropped), at most
// MAX_BATCH problems a call, texts are cut short, emails / links / long numbers are taken out, bots are ignored, a screenshot is at
// most 400 KB. One write per problem kind and message (counted), never a log line per event.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {createHash} = require('node:crypto');

const APPS = ['customer', 'vendor', 'staff', 'admin'];
const KINDS = ['crash', 'error', 'login', 'otp', 'email', 'location', 'upload', 'api', 'slow'];
const DEVICE_DAILY_CAP = 30;
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

/// The checked header of a call: which app, its version and the device ('' when not sent).
function header(data = {}) {
  const app = APPS.includes(data.app) ? data.app : null;
  if (!app) throw new HttpsError('invalid-argument', `app must be one of ${APPS.join(', ')}`);
  return {
    app,
    platform: data.platform === 'android' ? 'android' : 'web',
    version: clip(data.version, 30),
    device: clean(data.device, 80),
    deviceId: clip(data.deviceId, 100),
  };
}

/// The Vendor / Staff ID of the signed-in person, so the admin sees whose app it was ('' for customers and visitors).
async function userCode(db, auth) {
  if (!auth?.uid) return '';
  const role = auth.token?.role;
  try {
    if (role === 'vendor') return String((await db.collection('vendors').doc(auth.uid).get()).data()?.vendorCode || '');
    if (role === 'staff') {
      const d = (await db.collection('fieldStaff').doc(auth.uid).get()).data();
      return String(d?.staffCode || d?.code || '');
    }
  } catch { /* the code is only a label */ }
  return '';
}

/// Takes [n] of the device's daily allowance ([field] 'count' or 'reports'); returns how many may be kept.
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

/// Saves a batch of problems (the tests call it with a fake request).
async function saveProblems(db, request, now = Date.now()) {
  if (isBot(request)) return {saved: 0};
  const data = request.data || {};
  const h = header(data);
  const list = (Array.isArray(data.problems) ? data.problems : []).slice(0, MAX_BATCH)
    .map(p => ({kind: KINDS.includes(p?.kind) ? p.kind : 'error', message: clean(p?.message, 300), screen: clip(p?.screen, 60), ms: Number.isFinite(Number(p?.ms)) ? Math.round(Number(p.ms)) : null}))
    .filter(p => p.message);
  if (!list.length) return {saved: 0};
  const allowed = await takeAllowance(db, deviceKeyOf(h, request), list.length, 'count', DEVICE_DAILY_CAP, now);
  const keep = list.slice(0, allowed);
  if (!keep.length) return {saved: 0};
  const role = String(request.auth?.token?.role || '');
  const code = await userCode(db, request.auth);
  const at = Timestamp.fromMillis(now);
  const batch = db.batch();
  const kinds = {};
  for (const p of keep) {
    kinds[p.kind] = (kinds[p.kind] || 0) + 1;
    batch.set(db.collection('appProblems').doc(problemId(h.app, h.platform, p.kind, p.message)), {
      app: h.app, platform: h.platform, kind: p.kind, message: p.message, screen: p.screen, count: FieldValue.increment(1), lastAt: at,
      lastVersion: h.version, lastDevice: h.device, lastRole: role, lastUserCode: code, ...(p.ms != null ? {lastMs: p.ms} : {}),
    }, {merge: true});
  }
  batch.set(db.collection('appProblemsDaily').doc(`${dayKey(now)}~${h.app}~${h.platform}`), {
    day: dayKey(now), app: h.app, platform: h.platform, total: FieldValue.increment(keep.length),
    kinds: Object.fromEntries(Object.entries(kinds).map(([k, n]) => [k, FieldValue.increment(n)])),
  }, {merge: true});
  await batch.commit();
  return {saved: keep.length};
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
exports.reportProblem = onCall({...options, memory: '256MiB'}, async request => saveReport(getFirestore(), getStorage().bucket(), request));

exports._test = {saveProblems, saveReport, header, clean, fingerprint, problemId, screenshotOf, KINDS, DEVICE_DAILY_CAP, REPORTS_PER_DAY, dayKey};
