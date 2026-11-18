// App problems module (owner spec F + G): problems are counted per kind and message with the app, version, device and Vendor / Staff
// ID; a device's daily cap and the bot filter hold; a report keeps its screenshot. Emulator only for the writes.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {saveProblems, saveReport, header, clean, fingerprint, problemId, screenshotOf, DEVICE_DAILY_CAP, dayKey} = require('.')._test;

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=', 'base64').toString('base64');

test('the header is checked, private details are taken out, one problem has one id everywhere', () => {
  assert.throws(() => header({app: 'other'}), /app must be/);
  assert.deepEqual(header({app: 'vendor', platform: 'android', version: '1.0.12+22', device: 'Redmi 9 call 9876543210', deviceId: 'd1'}),
    {app: 'vendor', platform: 'android', version: '1.0.12+22', device: 'Redmi 9 call <number>', deviceId: 'd1', os: '', network: ''});
  assert.equal(clean('OTP for a@b.in failed https://x.y/z 123456', 100), 'OTP for <email> failed <link> <number>');
  assert.equal(fingerprint('vendor', 'otp', 'x'), fingerprint('vendor', 'otp', 'x'));
  assert.notEqual(fingerprint('vendor', 'otp', 'x'), fingerprint('staff', 'otp', 'x'));
  assert.equal(screenshotOf(''), null);
  assert.throws(() => screenshotOf(Buffer.from('GIF89a').toString('base64')), /PNG or JPEG/);
  assert.throws(() => screenshotOf(Buffer.concat([Buffer.from([0xff, 0xd8]), Buffer.alloc(90 * 1024)]).toString('base64')), /under 80 KB/);
  assert.equal(screenshotOf(PNG).type, 'image/png');
});

test('problems are counted with the Vendor ID; the device cap and the bot filter hold', emulated, async () => {
  const db = getFirestore();
  await db.collection('vendors').doc('vu1').set({vendorCode: 'VEN-NRPM-116-325'});
  const now = Date.parse('2026-11-17T06:00:00Z');
  const request = problems => ({
    auth: {uid: 'vu1', token: {role: 'vendor'}},
    rawRequest: {headers: {'user-agent': 'Dart/3.9'}, ip: '1.2.3.4'},
    data: {app: 'vendor', platform: 'android', version: '1.0.12+22', device: 'Redmi 9', deviceId: `dev-${now}`, problems},
  });
  const r = await saveProblems(db, request([{kind: 'otp', message: 'OTP not received', screen: 'login'}, {kind: 'otp', message: 'OTP not received', screen: 'login'}, {kind: 'upload', message: 'Photo upload failed: 403'}]), now);
  assert.equal(r.saved, 3);
  const otp = await db.collection('appProblems').doc(problemId('vendor', 'android', 'otp', 'OTP not received')).get();
  assert.equal(otp.data().count, 2);
  assert.equal(otp.data().lastUserCode, 'VEN-NRPM-116-325');
  assert.equal(otp.data().lastVersion, '1.0.12+22');
  const day = (await db.collection('appProblemsDaily').doc(`${dayKey(now)}~vendor~android`).get()).data();
  assert.equal(day.total, 3);
  assert.equal(day.kinds.otp, 2);
  // the cap: no more than DEVICE_DAILY_CAP in a day are kept
  let saved = 3;
  for (let i = 0; i < 5; i++) saved += (await saveProblems(db, request(Array.from({length: 10}, (_, j) => ({kind: 'error', message: `e${i}-${j}`}))), now)).saved;
  assert.equal(saved, DEVICE_DAILY_CAP);
  assert.equal((await saveProblems(db, request([{kind: 'error', message: 'one more'}]), now)).saved, 0);
  const bot = request([{kind: 'error', message: 'x'}]);
  bot.rawRequest.headers['user-agent'] = 'Googlebot';
  assert.equal((await saveProblems(db, bot, now + 86400000)).saved, 0);
});

test('a report keeps the text and the screenshot; at most 5 a day per device', emulated, async () => {
  const db = getFirestore();
  const files = new Map();
  const bucket = {file: name => ({save: async b => files.set(name, b)})};
  const now = Date.parse('2026-11-17T07:00:00Z');
  const req = {auth: null, rawRequest: {headers: {}}, data: {app: 'customer', platform: 'web', deviceId: `r-${now}`, text: 'Cart button does nothing', screen: 'cart', screenshot: PNG}};
  const {id} = await saveReport(db, bucket, req, now);
  const saved = (await db.collection('problemReports').doc(id).get()).data();
  assert.equal(saved.text, 'Cart button does nothing');
  assert.equal(saved.status, 'new');
  assert.equal(saved.screenshotPath, `reports/${id}.png`, 'in the US bucket');
  assert.ok(files.has(saved.screenshotPath));
  await assert.rejects(saveReport(db, bucket, {...req, data: {...req.data, text: ''}}, now), /Write what went wrong/);
  for (let i = 0; i < 4; i++) await saveReport(db, bucket, req, now);
  await assert.rejects(saveReport(db, bucket, req, now), /5 reports today/);
});
