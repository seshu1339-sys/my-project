const {test} = require('node:test');
const assert = require('node:assert/strict');
require('./index'); // starts the Firebase app
const {_pushCenter} = require('./push-center');

test('a push needs a title, a message and who gets it', () => {
  const ok = {title: 'Diwali offers', body: 'Big savings today', audience: 'all'};
  assert.equal(_pushCenter.message(ok).audience, 'all');
  assert.throws(() => _pushCenter.message({...ok, title: 'x'}), /title/);
  assert.throws(() => _pushCenter.message({...ok, body: ''}), /message/);
  assert.throws(() => _pushCenter.message({...ok, audience: 'everyone'}), /who gets it/);
  assert.throws(() => _pushCenter.message({...ok, audience: 'town'}), /town/);
  assert.throws(() => _pushCenter.message({...ok, audience: 'person'}), /email or account id/);
  assert.equal(_pushCenter.townKey('Krishna Bazar (Narsipatnam)'), 'narsipatnam');
});

test('the admin sends to everyone, a town or one person; opens are counted once; who has not opened; how many turned them off', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST}, async () => {
  process.env.PUSH_DRY_RUN = 'true';
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const fns = require('./index');
  const db = getFirestore();
  for (const c of ['notificationSubscribers', 'pushLog', 'pushTypeDaily', '_pushDryRun']) for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  await db.collection('_adminSessions').doc('pushAdmin').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  const admin = {auth: {uid: 'pushAdmin', token: {admin: true, email_verified: true}}};
  for (const [uid, pincode, enabled, token] of [['pushS1', '531116', true, true], ['pushS2', '533401', true, true], ['pushS3', '531116', true, false], ['pushS4', '531116', false, true]]) {
    await db.collection('notificationSubscribers').doc(uid).set({enabled, pincode});
    if (token) await db.collection('users').doc(uid).collection('pushTokens').doc('t1').set({token: `token-${uid}`});
    try { await getAuth().deleteUser(uid); } catch (_) { /* not there */ }
    await getAuth().createUser({uid, email: `${uid.toLowerCase()}@example.test`});
  }
  const send = data => fns.sendPushNotification.run({...admin, data: {title: 'Diwali offers', body: 'Big savings today', ...data}});

  await assert.rejects(() => fns.sendPushNotification.run({auth: {uid: 'pushS1', token: {email_verified: true}}, data: {title: 'Hi there', body: 'Hello all', audience: 'all'}}), /Administrator/);
  const all = await send({audience: 'all'});
  assert.deepEqual([all.recipients, all.sent, all.noToken, all.off], [3, 2, 1, 0], 'the 3 with notifications on; one has no device');
  const town = await send({audience: 'town', town: 'Narsipatnam'});
  assert.equal(town.recipients, 2, 'pushS1 and pushS3 are in Narsipatnam');
  const person = await send({audience: 'person', person: 'pushs1@example.test'});
  assert.deepEqual([person.recipients, person.sent], [1, 1]);
  const off = await send({audience: 'person', person: 'pushS4'});
  assert.deepEqual([off.recipients, off.off], [0, 1], 'a person who turned notifications off is not sent to');
  await assert.rejects(() => send({audience: 'person', person: 'nobody@example.test'}), /No account/);
  assert.equal((await db.collection('_pushDryRun').get()).size, 4);
  const log = (await db.collection('pushLog').doc(all.nid).get()).data();
  assert.deepEqual([log.title, log.audience, log.sent, log.status], ['Diwali offers', 'all', 2, 'done']);

  // opened: counted once per person; the rest are listed as not opened
  const open = uid => fns.trackPushOpen.run({auth: {uid, token: {}}, data: {nid: all.nid}});
  assert.deepEqual(await open('pushS1'), {counted: true});
  assert.deepEqual(await open('pushS1'), {counted: false});
  assert.equal((await db.collection('pushLog').doc(all.nid).get()).data().opened, 1);
  const notOpened = await fns.pushNotOpened.run({...admin, data: {nid: all.nid}});
  assert.deepEqual(notOpened.people.map(p => p.email), ['pushs2@example.test']);

  // automatic notifications: sent and opened per type and day
  await _pushCenter.countAutomaticSent('priceDrop', 3);
  await fns.trackPushOpen.run({auth: {uid: 'pushS2', token: {}}, data: {type: 'priceDrop'}});
  const day = new Date(Date.now() + 19800000).toISOString().slice(0, 10);
  const typeDay = (await db.collection('pushTypeDaily').doc(`priceDrop~${day}`).get()).data();
  assert.deepEqual([typeDay.sent, typeDay.opened], [3, 1]);

  // the audience: on, off, by town
  const audience = await fns.pushAudience.run({...admin, data: {}});
  assert.deepEqual([audience.on, audience.off], [3, 1]);
  assert.deepEqual(audience.towns.map(t => `${t.town}:${t.count}`), ['Narsipatnam:2', 'Ammajipeta:1'], 'by the town of the pincode in the India Post directory');
  delete process.env.PUSH_DRY_RUN;
});
