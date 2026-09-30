const {test} = require('node:test');
const assert = require('node:assert/strict');

// Real functions against the emulators; pushes are recorded in _pushDryRun
// instead of sent. Confirms fanOutOffer (via the scheduled notifyNewOffers
// check) actually geo-filters using each subscriber's last-known location,
// mirroring promotionMatchesLocation's client-side behaviour.
test('a geo-targeted offer only reaches subscribers inside its area; an untargeted offer still reaches everyone', {
  skip: !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST),
}, async () => {
  process.env.PUSH_DRY_RUN = 'true';
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const wipe = async name => { for (const d of (await db.collection(name).get()).docs) await d.ref.delete(); };
  const dry = async () => (await db.collection('_pushDryRun').get()).docs.map(d => d.data());
  try {
    await wipe('_pushDryRun'); await wipe('_notificationDeliveries'); await wipe('notificationSubscribers'); await wipe('promotions');
    await db.collection('settings').doc('business').set({name: 'Test'});

    // 'inside' sits within the rectangle below; 'outside' and 'nolocation'
    // do not (the latter has never shared a location at all).
    await db.collection('notificationSubscribers').doc('inside').set({enabled: true, pincode: '560001', latitude: 12.95, longitude: 77.6});
    await db.collection('users').doc('inside').collection('pushTokens').doc('t').set({token: 'tok-inside'});
    await db.collection('notificationSubscribers').doc('outside').set({enabled: true, pincode: '999999', latitude: 20.0, longitude: 80.0});
    await db.collection('users').doc('outside').collection('pushTokens').doc('t').set({token: 'tok-outside'});
    await db.collection('notificationSubscribers').doc('nolocation').set({enabled: true});
    await db.collection('users').doc('nolocation').collection('pushTokens').doc('t').set({token: 'tok-nolocation'});

    await db.collection('promotions').doc('rectAd').set({
      name: 'Rectangle-targeted ad', placement: 'carousel', active: true,
      geoShape: 'rectangle', targetRectangle: {north: 13.0, south: 12.9, east: 77.7, west: 77.5},
    });
    await db.collection('promotions').doc('everyAd').set({name: 'Everywhere ad', placement: 'carousel', active: true});

    await fns.notifyNewOffers.run({});
    const pushes = await dry();
    const byPromo = id => pushes.filter(p => p.data.promotionId === id);

    assert.deepEqual(new Set(byPromo('rectAd').map(p => p.uid)), new Set(['inside']), 'only the in-range subscriber gets the rectangle-targeted offer');
    assert.deepEqual(new Set(byPromo('everyAd').map(p => p.uid)), new Set(['inside', 'outside', 'nolocation']), 'an untargeted offer still reaches every subscriber regardless of location');
  } finally {
    await wipe('_pushDryRun'); await wipe('_notificationDeliveries'); await wipe('notificationSubscribers'); await wipe('promotions');
  }
});
