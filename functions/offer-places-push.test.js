const {test} = require('node:test');
const assert = require('node:assert/strict');

// An offer made for towns / districts / states must be pushed only to subscribers at those places
// (found from their saved pincode). Real functions against the emulators; pushes are recorded in
// _pushDryRun instead of sent.
test('offer pushes follow the offer\'s places', {skip: !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST)}, async () => {
  process.env.PUSH_DRY_RUN = 'true';
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const wipe = async name => { for (const d of (await db.collection(name).get()).docs) await d.ref.delete(); };
  const dry = async () => (await db.collection('_pushDryRun').get()).docs.map(d => d.data());
  await wipe('_pushDryRun'); await wipe('_notificationDeliveries'); await wipe('notificationSubscribers'); await wipe('promotions');
  await db.collection('settings').doc('business').set({name: 'Test'});
  const subscribers = {raj: '533101', vij: '520001', war: '506002', outside: '560001', noplace: undefined};
  for (const [uid, pincode] of Object.entries(subscribers)) {
    await db.collection('notificationSubscribers').doc(uid).set({enabled: true, ...(pincode ? {pincode} : {})});
    await db.collection('users').doc(uid).collection('pushTokens').doc('t').set({token: 'tok-' + uid});
  }
  const offer = (id, locations) => db.collection('promotions').doc(id).set({name: id, placement: 'carousel', active: true, ...(locations ? {locations} : {})});
  await offer('everyone');
  await offer('rajahmundryOnly', 'Rajahmundry (East Godavari)');
  await offer('krishnaDistrict', 'district:Krishna');
  await offer('telangana', 'state:Telangana');
  await offer('twoPlaces', 'Rajahmundry (East Godavari), district:Krishna');
  await fns.notifyNewOffers.run({});
  const pushes = await dry();
  const who = id => pushes.filter(p => p.data.promotionId === id).map(p => p.uid).sort();
  assert.deepEqual(who('everyone'), ['noplace', 'outside', 'raj', 'vij', 'war'], 'a general offer reaches everyone');
  assert.deepEqual(who('rajahmundryOnly'), ['raj']);
  assert.deepEqual(who('krishnaDistrict'), ['vij']);
  assert.deepEqual(who('telangana'), ['war']);
  assert.deepEqual(who('twoPlaces'), ['raj', 'vij']);
});
