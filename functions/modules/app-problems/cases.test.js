// AI Agent + Health System, parts 1-2 (17 Nov 2026): the side of a problem (user / device / our), the burst alert to the admin, the
// people counted once. Cost cuts part 3 (18 Nov 2026): ONE record per problem (no record per person or per time), its last 3 examples,
// at most 3 screenshots a problem in the US bucket, none for a slow save or many taps, deleted when solved.
// Emulator only for the writes.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {healthConfig, deviceParts, sideOf, nextBurst, byImpact, keyOf} = require('./cases');
const {pushAdmins} = require('./alerts');
const {saveProblems, problemId, problemOf, autoShotOf, cleanShots, markSolved, resetConfig, MAX_PEOPLE} = require('.')._test;

/// A stand-in for the US screenshot bucket: the saved files by path.
function fakeBucket() {
  const files = new Map();
  return {
    files,
    file: name => ({save: async bytes => files.set(name, bytes)}),
    deleteFiles: async ({prefix}) => { for (const k of [...files.keys()]) if (k.startsWith(prefix)) files.delete(k); },
  };
}

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 74, 70, 73, 70]).toString('base64');
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=', 'base64').toString('base64');

test('the admin limits stay in a safe range; device strings become model and Android version', () => {
  assert.deepEqual(healthConfig({}), {burstCount: 6, burstMinutes: 60, burstSides: ['our', 'device']});
  assert.deepEqual(healthConfig({burstCount: '10', burstMinutes: 30, burstSides: 'our, user'}), {burstCount: 10, burstMinutes: 30, burstSides: ['our', 'user']});
  assert.equal(healthConfig({burstCount: 1}).burstCount, 6, 'below the minimum: the default');
  assert.deepEqual(deviceParts('Xiaomi Redmi 9 (Android 11)'), {model: 'Xiaomi Redmi 9', os: 'Android 11'});
  assert.deepEqual(deviceParts('chrome Win32', ''), {model: 'chrome Win32', os: 'unknown'});
  assert.equal(keyOf('a.b/c~d'), 'a_b_c_d');
});

test('USER side stays user; one phone model for most people is DEVICE side; else OUR side', () => {
  assert.equal(sideOf({clientSide: 'user', users: 9, devices: {'Redmi 9': 9}}), 'user');
  assert.equal(sideOf({clientSide: 'our', users: 1, devices: {'Redmi 9': 1}}), 'our', 'one person is not enough to blame the phone');
  assert.equal(sideOf({clientSide: 'our', users: 4, devices: {'Redmi 9': 5}, oses: {'Android 11': 5}}), 'device');
  assert.equal(sideOf({clientSide: 'our', users: 5, devices: {A: 2, B: 2, C: 1}, oses: {'Android 10': 1, 'Android 13': 4}}), 'our');
  assert.equal(sideOf({clientSide: 'our', users: 5, devices: {A: 2, B: 2, C: 1}, oses: {'Android 9': 5}}), 'device', 'every case on one Android version');
});

test('a burst alerts once per window at the admin count; an old window starts again', () => {
  const cfg = {burstCount: 6, burstMinutes: 60};
  const t0 = Date.parse('2026-11-17T10:00:00Z');
  let b = null;
  let alerts = 0;
  for (let i = 0; i < 8; i++) {
    const r = nextBurst(b, 1, t0 + i * 60000, cfg);
    b = r.burst;
    if (r.alert) alerts++;
  }
  assert.equal(alerts, 1);
  assert.equal(b.n, 8);
  const later = nextBurst(b, 1, t0 + 2 * 3600000, cfg);
  assert.equal(later.burst.n, 1);
  assert.equal(later.alert, false);
});

test('most affected people first, then most errors', () => {
  const list = [{id: 'a', users: 1, count: 50}, {id: 'b', users: 7, count: 9}, {id: 'c', users: 7, count: 20}];
  assert.deepEqual(list.sort(byImpact).map(x => x.id), ['c', 'b', 'a']);
});

test('a problem from the app is checked: kind, side, cause, a JPEG screenshot only, none for a slow save or many taps', () => {
  const p = problemOf({kind: 'tap', message: 'No answer to Save after 3 taps', option: 'Save', side: 'device', cause: 'no_response!', shot: JPEG});
  assert.equal(p.kind, 'tap');
  assert.equal(p.side, 'device');
  assert.equal(p.cause, 'no_response');
  assert.equal(p.shot, null, 'many taps: counted only, never a screenshot');
  assert.equal(problemOf({kind: 'slow', message: 'Slow save x', shot: JPEG}).shot, null, 'slow: counted only');
  assert.equal(problemOf({kind: 'stuck', message: 'Kept loading', shot: JPEG}).shot.type, 'image/jpeg');
  assert.equal(problemOf({kind: 'x', side: 'them'}).kind, 'error');
  assert.equal(problemOf({side: 'them'}).side, 'our');
  assert.equal(autoShotOf(PNG), null, 'automatic screenshots are JPEG');
  assert.equal(autoShotOf('A'.repeat(200000)), null, 'too big');
});

test('the admin push goes to every saved device; dead tokens are removed', emulated, async () => {
  const db = getFirestore();
  await db.collection('adminPushTokens').doc('good').set({uid: 'a1'});
  await db.collection('adminPushTokens').doc('dead').set({uid: 'a1'});
  let sent;
  const n = await pushAdmins(db, 'T', 'B', {send: async m => {
    sent = m;
    return {successCount: 1, responses: m.tokens.map(t => (t === 'dead' ? {success: false, error: {code: 'messaging/registration-token-not-registered'}} : {success: true}))};
  }});
  assert.equal(n, 1);
  assert.deepEqual([...sent.tokens].sort(), ['dead', 'good']);
  assert.match(sent.webpush.fcmOptions.link, /open=page\.health/);
  assert.equal((await db.collection('adminPushTokens').doc('dead').get()).exists, false);
  await db.collection('adminPushTokens').doc('good').delete();
});

test('one record per problem with its last 3 examples; people counted once; 3 screenshots at most; 6 in an hour alerts once', emulated, async () => {
  const db = getFirestore();
  resetConfig();
  await db.collection('settings').doc('health').set({burstCount: 6, burstMinutes: 60});
  await db.collection('vendors').doc('vp1').set({vendorCode: 'VEN-1', phone: '9000000001'});
  await db.collection('adminPushTokens').doc('t1').set({uid: 'a1'});
  const bucket = fakeBucket();
  const pushes = [];
  const send = async m => {
    pushes.push(m);
    return {successCount: 1, responses: [{success: true}]};
  };
  const t0 = Date.parse('2026-11-17T11:00:00Z');
  const call = (uid, i) => ({
    auth: uid ? {uid, token: {role: 'vendor'}} : null,
    rawRequest: {headers: {'user-agent': 'Dart/3.9'}, ip: `9.9.9.${i}`},
    data: {
      app: 'vendor', platform: 'android', version: '1.0.13+23', device: 'Xiaomi Redmi 9 (Android 11)', os: 'Android 11', network: 'mobile',
      deviceId: `burst-${i}-${t0}`,
      problems: [{kind: 'stuck', message: 'Add item kept loading', screen: 'add_item', option: 'Save item', side: 'our', cause: 'no_response', shot: JPEG}],
    },
  });
  const first = await saveProblems(db, call('vp1', 1), t0, {send, bucket});
  const id = problemId('vendor', 'android', 'stuck', 'Add item kept loading');
  assert.deepEqual(first.problems, [id]);
  let p = (await db.collection('appProblems').doc(id).get()).data();
  const e = p.examples[0];
  assert.equal(e.phone, '9000000001');
  assert.equal(e.userCode, 'VEN-1');
  assert.equal(e.model, 'Xiaomi Redmi 9');
  assert.equal(e.os, 'Android 11');
  assert.equal(e.network, 'mobile');
  assert.equal(e.option, 'Save item');
  assert.match(e.shot, /^problems\/vendor~android~stuck~[0-9a-f]{16}\/\d+-1\.jpg$/);
  assert.equal(p.shots, 1);
  assert.equal(p.lastShot, e.shot);
  assert.ok(bucket.files.has(e.shot), 'the screenshot is in the US bucket');
  await saveProblems(db, call('vp1', 1), t0 + 60000, {send, bucket}); // the same person again: still one person
  p = (await db.collection('appProblems').doc(id).get()).data();
  assert.equal(p.users, 1);
  assert.equal(p.count, 2);
  for (let i = 2; i <= 5; i++) await saveProblems(db, call(null, i), t0 + i * 60000, {send, bucket});
  p = (await db.collection('appProblems').doc(id).get()).data();
  assert.equal(p.users, 5);
  assert.equal(p.count, 6);
  assert.equal(p.side, 'device', 'everyone on one phone model');
  assert.equal(p.devices['Xiaomi Redmi 9'], 6);
  assert.equal(p.examples.length, 3, 'only the last 3 times are kept');
  assert.equal(p.shots, 3, 'at most 3 screenshots a problem');
  assert.equal(p.shotPaths.length, 3);
  assert.equal(bucket.files.size, 3);
  assert.equal(pushes.length, 1, 'the 6th time in the hour alerts the admin');
  assert.match(pushes[0].notification.title, /Vendor app \(Android\): 6 times in 60 min/);
  const alert = (await db.collection('healthAlerts').doc(id).get()).data();
  assert.equal(alert.open, true);
  assert.equal(alert.n, 6);
  await saveProblems(db, call(null, 7), t0 + 7 * 60000, {send, bucket});
  assert.equal(pushes.length, 1, 'once per window');
  // No record per person or per time any more.
  assert.equal((await db.collection('appCases').where('problemId', '==', id).get()).size, 0);
  assert.equal((await db.collection('appShots').where('problemId', '==', id).get()).size, 0);
  assert.equal((await db.collection('appProblems').doc(id).collection('who').get()).size, 0);
  // Solved: the screenshots go; the problem may take new ones if it comes back.
  assert.equal(await markSolved(db, id, t0 + 86400000, {bucket}), 3);
  p = (await db.collection('appProblems').doc(id).get()).data();
  assert.equal(p.status, 'solved');
  assert.equal(p.shots, 0);
  assert.equal(bucket.files.size, 0);
  assert.ok(p.examples.every(x => x.shot === ''));
  await saveProblems(db, call(null, 8), t0 + 2 * 86400000, {send, bucket});
  p = (await db.collection('appProblems').doc(id).get()).data();
  assert.equal(p.status, 'open');
  assert.equal(p.shots, 1);
  await db.collection('adminPushTokens').doc('t1').delete();
});

test('a slow save or many taps are counted, never photographed', emulated, async () => {
  const db = getFirestore();
  resetConfig();
  const bucket = fakeBucket();
  const now = Date.parse('2026-11-18T05:00:00Z');
  await saveProblems(db, {auth: null, rawRequest: {headers: {}, ip: '7.7.7.7'}, data: {
    app: 'customer', platform: 'android', deviceId: `slow-${now}`,
    problems: [{kind: 'slow', message: 'Slow save cart', shot: JPEG}, {kind: 'tap', message: 'No answer to Buy', shot: JPEG}],
  }}, now, {bucket});
  const slow = (await db.collection('appProblems').doc(problemId('customer', 'android', 'slow', 'Slow save cart')).get()).data();
  assert.equal(slow.count, 1);
  assert.equal(slow.shots, undefined);
  assert.equal(bucket.files.size, 0);
});

test('past 100 people the count shows 100+ and the record stays small', emulated, async () => {
  const db = getFirestore();
  resetConfig();
  const now = Date.parse('2026-11-18T06:00:00Z');
  const id = problemId('staff', 'android', 'error', 'Many people');
  await db.collection('appProblems').doc(id).set({people: Array.from({length: MAX_PEOPLE}, (_, i) => `p${i}`), users: MAX_PEOPLE, count: MAX_PEOPLE});
  await saveProblems(db, {auth: null, rawRequest: {headers: {}, ip: '8.8.8.8'}, data: {app: 'staff', platform: 'android', deviceId: `many-${now}`, problems: [{kind: 'error', message: 'Many people'}]}}, now);
  const p = (await db.collection('appProblems').doc(id).get()).data();
  assert.equal(p.users, MAX_PEOPLE);
  assert.equal(p.usersMore, true);
  assert.equal(p.people.length, MAX_PEOPLE);
  assert.equal(p.count, MAX_PEOPLE + 1);
});

test('the old Firestore screenshots past their 30 days are deleted', emulated, async () => {
  const db = getFirestore();
  const t0 = Date.parse('2026-11-01T00:00:00Z');
  const {Timestamp} = require('firebase-admin/firestore');
  await db.collection('appShots').doc('old-1').set({problemId: 'x', data: JPEG, expiresAt: Timestamp.fromMillis(t0)});
  assert.ok((await cleanShots(db, t0 + 1000)) >= 1);
  assert.equal((await db.collection('appShots').doc('old-1').get()).exists, false);
});
