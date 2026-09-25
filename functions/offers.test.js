const {test} = require('node:test');
const assert = require('node:assert/strict');

// Real functions against the emulators; pushes are recorded in _pushDryRun instead of sent.
test('offers reach every subscriber once; admin can switch off or send manually', {skip: !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST)}, async () => {
  process.env.PUSH_DRY_RUN = 'true';
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  // Admin callables now also require a fresh OTP-verified session (see admin-otp.js).
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  const wipe = async name => { for (const d of (await db.collection(name).get()).docs) await d.ref.delete(); };
  const dry = async () => (await db.collection('_pushDryRun').get()).docs.map(d => d.data());
  const promo = async id => (await db.collection('promotions').doc(id).get()).data();
  try {
    await wipe('_pushDryRun'); await wipe('_notificationDeliveries'); await wipe('notificationSubscribers'); await wipe('promotions');
    await db.collection('settings').doc('business').set({name: 'Test'});
    // 60 subscribers with a device (more than one parallel batch), one without a device, one who switched alerts off
    for (let i = 0; i < 60; i++) {
      await db.collection('notificationSubscribers').doc('sub' + i).set({enabled: true});
      await db.collection('users').doc('sub' + i).collection('pushTokens').doc('t').set({token: 'tok' + i});
    }
    await db.collection('notificationSubscribers').doc('nodevice').set({enabled: true});
    await db.collection('notificationSubscribers').doc('off').set({enabled: false});
    await db.collection('users').doc('off').collection('pushTokens').doc('t').set({token: 'tokoff'});
    await db.collection('promotions').doc('sale').set({name: 'Diwali sale', description: '20% off everything', placement: 'carousel', active: true});
    await db.collection('promotions').doc('ticker').set({name: 'SHOP LOCAL', placement: 'ticker', active: true});
    await db.collection('promotions').doc('tickerOn').set({name: 'Free delivery today', placement: 'ticker', notifySubscribers: 'true', active: true});
    await db.collection('promotions').doc('quiet').set({name: 'Quiet banner', placement: 'ad', notifySubscribers: 'false', active: true});
    await db.collection('promotions').doc('later').set({name: 'Coming soon', placement: 'carousel', startsAt: '2999-01-01', active: true});
    await db.collection('promotions').doc('old').set({name: 'Expired', placement: 'carousel', endsAt: '2000-01-01', active: true});

    // ---- the scheduled check
    await fns.notifyNewOffers.run({});
    let pushes = await dry();
    const byPromo = id => pushes.filter(p => p.data.promotionId === id);
    assert.equal(byPromo('sale').length, 60, 'every subscriber with a device gets the offer');
    assert.equal(new Set(byPromo('sale').map(p => p.uid)).size, 60);
    assert.ok(!byPromo('sale').some(p => ['off', 'nodevice'].includes(p.uid)), 'alerts-off and no-device subscribers get nothing');
    assert.equal(byPromo('sale')[0].notification.title, 'New offer'); assert.equal(byPromo('sale')[0].notification.body, 'Diwali sale - 20% off everything');
    assert.equal(byPromo('sale')[0].data.type, 'offer');
    assert.equal(byPromo('tickerOn').length, 60, 'a ticker notifies only when the admin asks it to');
    assert.equal(byPromo('ticker').length, 0); assert.equal(byPromo('quiet').length, 0);
    assert.equal(byPromo('later').length, 0); assert.equal(byPromo('old').length, 0);
    const sale = await promo('sale'); assert.equal(sale.notifiedCount, 60); assert.ok(sale.notifiedKey && sale.notifiedAt);
    const total = pushes.length;

    // ---- nothing repeats: another poll, an edit of the offer, a re-delivered publish event
    await fns.notifyNewOffers.run({});
    assert.equal((await dry()).length, total);
    await db.collection('promotions').doc('sale').update({name: 'Diwali mega sale'});
    await fns.notifyOfferPublished.run({data: {before: {data: () => ({})}, after: {exists: true, data: () => ({})}}, params: {promotionId: 'sale'}});
    assert.equal((await dry()).length, total);

    // ---- publishing a new offer notifies straight away (trigger), and a rescheduled start notifies again
    await db.collection('promotions').doc('flash').set({name: 'Flash deal', placement: 'boxes', active: true});
    await fns.notifyOfferPublished.run({data: {before: undefined, after: {exists: true, data: () => ({name: 'Flash deal'})}}, params: {promotionId: 'flash'}});
    pushes = await dry(); assert.equal(byPromo('flash').length, 60);
    await db.collection('promotions').doc('flash').update({startsAt: '2020-01-01'});
    await fns.notifyOfferPublished.run({data: {before: {data: () => ({notifiedKey: 'offer:flash:initial'})}, after: {exists: true, data: () => ({notifiedKey: 'offer:flash:initial', startsAt: '2020-01-01'})}}, params: {promotionId: 'flash'}});
    pushes = await dry(); assert.equal(byPromo('flash').length, 120, 'a new go-live time is a new notification');

    // ---- the admin switch: automatic off stops new offers, manual send still works
    await db.collection('settings').doc('business').set({offerNotificationsEnabled: 'false'}, {merge: true});
    await db.collection('promotions').doc('held').set({name: 'Held back', placement: 'carousel', active: true});
    await fns.notifyNewOffers.run({});
    pushes = await dry(); assert.equal(byPromo('held').length, 0, 'automatic offers are off');
    await assert.rejects(() => fns.sendOfferNotification.run({data: {promotionId: 'held'}}), /Sign in/);
    await assert.rejects(() => fns.sendOfferNotification.run({auth: {uid: 'u', token: {email_verified: true}}, data: {promotionId: 'held'}}), /Administrator/);
    await assert.rejects(() => fns.sendOfferNotification.run({...admin, data: {promotionId: 'nope'}}), /not found/i);
    await assert.rejects(() => fns.sendOfferNotification.run({...admin, data: {promotionId: 'later'}}), /live right now/);   // not live yet
    await assert.rejects(() => fns.sendOfferNotification.run({...admin, data: {promotionId: '../x'}}), /Choose an offer/);
    const manual = await fns.sendOfferNotification.run({...admin, data: {promotionId: 'held'}});
    assert.equal(manual.status, 'sent'); assert.equal(manual.sent, 60);
    pushes = await dry(); assert.equal(byPromo('held').length, 60);
    const again = await fns.sendOfferNotification.run({...admin, data: {promotionId: 'held'}});      // double click
    assert.equal(again.sent, 0); assert.equal(again.duplicate, 60);
    assert.equal(byPromo('held').length, 60);
    // manual send also works for an offer the admin excluded from automatic notifications
    const quiet = await fns.sendOfferNotification.run({...admin, data: {promotionId: 'quiet'}}); assert.equal(quiet.sent, 60);

    // ---- how many people would receive it
    assert.deepEqual(await fns.offerAudienceSize.run({...admin, data: {}}), {subscribers: 61});
    await assert.rejects(() => fns.offerAudienceSize.run({auth: {uid: 'u', token: {email_verified: true}}, data: {}}), /Administrator/);
  } finally {
    await wipe('_pushDryRun'); await wipe('_notificationDeliveries'); await wipe('notificationSubscribers'); await wipe('promotions');
    await db.collection('settings').doc('business').set({offerNotificationsEnabled: 'true'}, {merge: true});
  }
});
