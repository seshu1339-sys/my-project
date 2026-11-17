// AI Agent + Health System, parts 1-2 (17 Nov 2026): the side of a problem (user / device / our), the burst alert to the admin, the
// people counted once, each case kept with its details and screenshot, and the screenshots deleted after 30 days or when solved.
// Emulator only for the writes.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {healthConfig, deviceParts, sideOf, nextBurst, byImpact, keyOf} = require('./cases');
const {pushAdmins} = require('./alerts');
const {saveProblems, problemId, problemOf, autoShotOf, cleanShots, resetConfig} = require('.')._test;

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

test('a problem from the app is checked: kind, side, cause, a JPEG screenshot only', () => {
  const p = problemOf({kind: 'tap', message: 'No answer to Save after 3 taps', option: 'Save', side: 'device', cause: 'no_response!', shot: JPEG});
  assert.equal(p.kind, 'tap');
  assert.equal(p.side, 'device');
  assert.equal(p.cause, 'no_response');
  assert.equal(p.shot, JPEG);
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

test('each case is kept with its details; people are counted once; 6 in an hour alerts the admin once', emulated, async () => {
  const db = getFirestore();
  resetConfig();
  await db.collection('settings').doc('health').set({burstCount: 6, burstMinutes: 60});
  await db.collection('vendors').doc('vp1').set({vendorCode: 'VEN-1', phone: '9000000001'});
  await db.collection('adminPushTokens').doc('t1').set({uid: 'a1'});
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
      problems: [{kind: 'tap', message: 'No answer to Save item', screen: 'add_item', option: 'Save item', side: 'our', cause: 'no_response', shot: JPEG}],
    },
  });
  const first = await saveProblems(db, call('vp1', 1), t0, {send});
  assert.equal(first.cases.length, 1);
  const c = (await db.collection('appCases').doc(first.cases[0]).get()).data();
  assert.equal(c.phone, '9000000001');
  assert.equal(c.userCode, 'VEN-1');
  assert.equal(c.model, 'Xiaomi Redmi 9');
  assert.equal(c.os, 'Android 11');
  assert.equal(c.network, 'mobile');
  assert.equal(c.option, 'Save item');
  assert.equal(c.shot, true);
  assert.equal((await db.collection('appShots').doc(first.cases[0]).get()).data().data, JPEG);
  await saveProblems(db, call('vp1', 1), t0 + 60000, {send}); // the same person again: still one person
  const id = problemId('vendor', 'android', 'tap', 'No answer to Save item');
  let p = (await db.collection('appProblems').doc(id).get()).data();
  assert.equal(p.users, 1);
  assert.equal(p.count, 2);
  for (let i = 2; i <= 5; i++) await saveProblems(db, call(null, i), t0 + i * 60000, {send});
  p = (await db.collection('appProblems').doc(id).get()).data();
  assert.equal(p.users, 5);
  assert.equal(p.count, 6);
  assert.equal(p.side, 'device', 'everyone on one phone model');
  assert.equal(p.devices['Xiaomi Redmi 9'], 6);
  assert.equal(pushes.length, 1, 'the 6th case in the hour alerts the admin');
  assert.match(pushes[0].notification.title, /Vendor app \(Android\): 6 times in 60 min/);
  const alert = (await db.collection('healthAlerts').doc(id).get()).data();
  assert.equal(alert.open, true);
  assert.equal(alert.n, 6);
  await saveProblems(db, call(null, 7), t0 + 7 * 60000, {send});
  assert.equal(pushes.length, 1, 'once per window');
  // screenshots: those past 30 days and those of solved problems are deleted
  const shots = await db.collection('appShots').where('problemId', '==', id).get();
  assert.ok(shots.size >= 2);
  await shots.docs[0].ref.update({solved: true});
  assert.equal(await cleanShots(db, t0 + 31 * 86400000), shots.size);
  await db.collection('adminPushTokens').doc('t1').delete();
});
