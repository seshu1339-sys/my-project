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

test('moving notifies once about the offers of shops within the admin km, never far ones (distance rule)', {skip: !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST)}, async () => {
  process.env.PUSH_DRY_RUN = 'true';
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const wipe = async name => { for (const d of (await db.collection(name).get()).docs) await d.ref.delete(); };
  const dry = async () => (await db.collection('_pushDryRun').get()).docs.map(d => d.data());
  await wipe('_pushDryRun'); await wipe('_notificationDeliveries'); await wipe('notificationSubscribers'); await wipe('promotions'); await wipe('vendorOffers');
  await db.collection('settings').doc('business').set({name: 'Test', radiusKm: 10});
  await db.collection('users').doc('u1').collection('pushTokens').doc('t').set({token: 'tok'});
  // Two shops: one in Kancharapalem (Visakhapatnam), one in Narsipatnam (about 70 km away).
  await db.collection('shops').doc('kpl').set({name: 'Kancharapalem Kirana', latitude: 17.735, longitude: 83.280});
  await db.collection('shops').doc('nrp').set({name: 'Narsipatnam Store', latitude: 17.667, longitude: 82.612});
  await db.collection('promotions').doc('near').set({name: 'KPL SALE', placement: 'carousel', active: true, radiusShopId: 'kpl'});
  await db.collection('promotions').doc('far').set({name: 'NRP SALE', placement: 'carousel', active: true, radiusShopId: 'nrp'});
  await db.collection('promotions').doc('general').set({name: 'NO SHOP', placement: 'carousel', active: true});
  await db.collection('vendorOffers').doc('vo1').set({title: 'Sweets box', status: 'live', shopId: 'kpl', endsAt: Timestamp.fromMillis(Date.now() + 3600000)});
  const vizag = {enabled: true, latitude: 17.734, longitude: 83.279, area: 'Kancharapalem'};
  const change = async (before, after) => {
    const snap = d => ({exists: !!d, data: () => d});
    // The trigger fires after the customer's document was written; push sending reads it again.
    await db.collection('notificationSubscribers').doc('u1').set(after);
    await fns.notifyLocationOffers.run({params: {uid: 'u1'}, data: {before: snap(before), after: snap(after)}});
  };
  // Narsipatnam -> Kancharapalem: the offers of the Kancharapalem shop only, with the area name.
  await change({enabled: true, latitude: 17.667, longitude: 82.612}, vizag);
  let pushes = await dry();
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].notification.title, 'Offers near Kancharapalem');
  assert.match(pushes[0].notification.body, /KPL SALE/);
  assert.match(pushes[0].notification.body, /Sweets box/, "the vendors' live offers too");
  assert.doesNotMatch(pushes[0].notification.body, /NRP|NO SHOP/);
  // A refresh 200 m away is not a move: nothing.
  await change(vizag, {...vizag, latitude: 17.7355});
  assert.equal((await dry()).length, 1);
  // Back again within 24 h with the same offers: no repeat.
  await change({enabled: true, latitude: 17.667, longitude: 82.612}, vizag);
  assert.equal((await dry()).length, 1, 'same area + same offers is not announced twice');
  // Somewhere with no shop near: nothing.
  await change(vizag, {enabled: true, latitude: 28.61, longitude: 77.21});
  assert.equal((await dry()).length, 1);
  // The admin master switch stops location notices.
  await db.collection('settings').doc('business').set({name: 'Test', radiusKm: 10, offerNotificationsEnabled: false});
  await wipe('_notificationDeliveries');
  await change({enabled: true, latitude: 28.61, longitude: 77.21}, vizag);
  assert.equal((await dry()).length, 1, 'the admin master switch stops location notices');
  await wipe('vendorOffers'); await wipe('promotions');
  for (const id of ['kpl', 'nrp']) await db.collection('shops').doc(id).delete();
});
