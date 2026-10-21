const {test} = require('node:test');
const assert = require('node:assert/strict');
const {locationOffers, locationNoticeKey, locationNoticeCopy} = require('./notifications-domain');

const place = {town: 'Rajahmundry', district: 'East Godavari', state: 'Andhra Pradesh'};
const offer = (id, extra) => ({id, data: {name: id, placement: 'carousel', active: true, ...extra}});

test('locationOffers keeps only live offers aimed at the place', () => {
  const list = locationOffers([
    offer('general'), // no places: not a location offer
    offer('raj', {locations: 'Rajahmundry (East Godavari)'}),
    offer('dist', {locations: 'district:East Godavari'}),
    offer('other', {locations: 'Anakapalle (Anakapalli)'}),
    offer('off', {locations: 'Rajahmundry (East Godavari)', active: false}),
    offer('muted', {locations: 'Rajahmundry (East Godavari)', notifySubscribers: false}),
    offer('ticker', {locations: 'Rajahmundry (East Godavari)', placement: 'ticker'}),
  ], place);
  assert.deepEqual(list.map(o => o.id), ['dist', 'raj']);
});

test('notice key is per place and offers; copy names the town', () => {
  const a = [offer('raj', {locations: 'Rajahmundry (East Godavari)', name: 'Big Sale'})];
  assert.equal(locationNoticeKey(place, a), locationNoticeKey(place, a));
  assert.notEqual(locationNoticeKey(place, a), locationNoticeKey({...place, town: 'Kakinada'}, a));
  assert.notEqual(locationNoticeKey(place, a), locationNoticeKey(place, [...a, offer('x')]));
  const copy = locationNoticeCopy(place, a);
  assert.equal(copy.title, 'Offers in Rajahmundry');
  assert.match(copy.body, /Big Sale/);
});

test('moving between places notifies once per place, only that place\'s offers', {skip: !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST)}, async () => {
  process.env.PUSH_DRY_RUN = 'true';
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const wipe = async name => { for (const d of (await db.collection(name).get()).docs) await d.ref.delete(); };
  const dry = async () => (await db.collection('_pushDryRun').get()).docs.map(d => d.data());
  await wipe('_pushDryRun'); await wipe('_notificationDeliveries'); await wipe('notificationSubscribers'); await wipe('promotions');
  await db.collection('settings').doc('business').set({name: 'Test'});
  await db.collection('users').doc('u1').collection('pushTokens').doc('t').set({token: 'tok'});
  const put = (id, locations) => db.collection('promotions').doc(id).set({name: id, placement: 'carousel', active: true, ...(locations ? {locations} : {})});
  await put('general'); await put('RAJ SALE', 'Rajahmundry (East Godavari)'); await put('ANAK SALE', 'Anakapalle (Anakapalli)');
  const sub = (pincode, enabled = true) => db.collection('notificationSubscribers').doc('u1').set({enabled, pincode}, {merge: true});
  const change = async (before, after) => {
    const snap = d => ({exists: !!d, data: () => d});
    await fns.notifyLocationOffers.run({params: {uid: 'u1'}, data: {before: snap(before), after: snap(after)}});
  };
  // A -> B: Rajahmundry (533101) only
  await sub('533101');
  await change({enabled: true, pincode: '531001'}, {enabled: true, pincode: '533101'});
  let pushes = await dry();
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].notification.title, 'Offers in Rajahmundry');
  assert.match(pushes[0].notification.body, /RAJ SALE/);
  assert.doesNotMatch(pushes[0].notification.body, /ANAK|general/);
  // same pincode written again (location refresh): nothing
  await change({enabled: true, pincode: '533101'}, {enabled: true, pincode: '533101'});
  assert.equal((await dry()).length, 1);
  // back to Rajahmundry within 24 h after another move with no offers: no repeat
  await change({enabled: true, pincode: '560001'}, {enabled: true, pincode: '533101'});
  assert.equal((await dry()).length, 1, 'same place + same offers is not announced twice');
  // a place with no tagged offers: nothing
  await change({enabled: true, pincode: '533101'}, {enabled: true, pincode: '520001'});
  assert.equal((await dry()).length, 1);
  // notifications switched off by the customer, or globally
  await change({enabled: true, pincode: '533101'}, {enabled: false, pincode: '531001'});
  assert.equal((await dry()).length, 1);
  await db.collection('settings').doc('business').set({name: 'Test', offerNotificationsEnabled: false});
  await wipe('_notificationDeliveries');
  await change({enabled: true, pincode: '520001'}, {enabled: true, pincode: '533101'});
  assert.equal((await dry()).length, 1, 'the admin master switch stops location notices');
});
