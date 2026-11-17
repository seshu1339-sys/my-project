// Vendor prices never run out (owner, 16 Nov 2026), and "Today's rate": the vendor's "Yes, same rates" and the daily reminder.
const {test} = require('node:test');
const assert = require('node:assert/strict');

test('a vendor price stays until the vendor changes it: no end, never removed, orders work; old ends are cleared once', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const {clearOldPriceEnds} = require('./vendor-prices');
  const db = getFirestore();
  assert.equal(fns.expireVendorPrices, undefined, 'the old 24-hour expiry is gone');
  const vendor = {auth: {uid: 'priceV', token: {role: 'vendor', email_verified: true}}};
  await db.collection('vendors').doc('priceV').set({vendorId: 'priceV', name: 'Price Shop', shopId: 'priceShop', status: 'approved'});
  await db.collection('vendorShopPhotos').doc('priceV_1').set({vendorId: 'priceV', slot: 1, status: 'approved'});
  await db.collection('productImageLibrary').doc('lib-price-tomato').set({name: 'Tomato', imageUrl: 'https://example.test/t.jpg', active: true});
  await db.collection('settings').doc('business').set({name: 'Test', defaultPaymentMethod: 'direct_vendor'});

  const before = Date.now();
  const made = await fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {libraryItemId: 'lib-price-tomato', unitType: 'kg', quantity: 2, price: 50}}});
  const ref = db.collection('products').doc(made.docId);
  let item = (await ref.get()).data();
  assert.ok(Date.parse(item.priceSetAt) >= before - 1000, 'when the price was set (for the Today\'s rate tick)');
  assert.equal(item.priceExpiresAt, undefined);
  assert.equal(item.endsAt, undefined, 'never hidden by time');

  // An item from before the rule, still carrying its old end, gets a new price: the end goes.
  await ref.update({priceExpiresAt: new Date(Date.now() - 1000).toISOString(), endsAt: new Date(Date.now() - 1000).toISOString()});
  await fns.submitVendorChange.run({...vendor, data: {type: 'price', collection: 'products', docId: made.docId, changes: {price: 46}}});
  item = (await ref.get()).data();
  assert.deepEqual([item.price, item.priceExpiresAt, item.endsAt], [46, undefined, undefined]);
  const customer = {auth: {uid: 'priceCustomer', token: {role: 'user', email_verified: true}}};
  const order = await fns.placeOrder.run({...customer, data: {items: [{productId: made.docId, quantity: 1}], pincode: '531116', address: '12 Main Road, Narsipatnam', phone: '9876543210', latitude: 17, longitude: 82, requestId: 'req-price-2'}});
  assert.ok(order.orderId);

  // Once: the old ends of the items saved before go; an exclusive item keeps its own end; a removed price shows again (no price).
  const old = new Date(Date.now() - 5000).toISOString();
  await db.collection('products').doc('old-price').set({name: 'Onion', price: 30, priceSetAt: old, priceExpiresAt: old, endsAt: old});
  await db.collection('products').doc('old-removed').set({name: 'Beans', priceExpired: true, priceSetAt: old, priceExpiresAt: old, endsAt: old});
  const own = new Date(Date.now() + 86400000).toISOString();
  await db.collection('products').doc('old-exclusive').set({name: 'Saree', isExclusive: true, price: 900, priceExpiresAt: old, expiresAt: own, endsAt: own});
  assert.ok(await clearOldPriceEnds(db) >= 3);
  const [p, r, e] = await Promise.all(['old-price', 'old-removed', 'old-exclusive'].map(async id => (await db.collection('products').doc(id).get()).data()));
  assert.deepEqual([p.price, p.priceExpiresAt, p.endsAt], [30, undefined, undefined]);
  assert.deepEqual([r.priceExpired, r.endsAt, r.price], [undefined, undefined, undefined]);
  assert.deepEqual([e.endsAt, e.priceExpiresAt], [own, undefined], 'the exclusive item keeps its own end');
  assert.equal(await clearOldPriceEnds(db), 0, 'nothing left');
});

test('"Yes, same rates": one field on the vendor and its copy on the shop; only an approved vendor', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  require('./index');
  const {confirmRates} = require('./vendor-rates')._vendorRates;
  const db = getFirestore();
  await db.collection('vendors').doc('rateV').set({status: 'approved', shopId: 'rateShop'});
  const now = Date.parse('2026-11-16T09:00:00+05:30');
  assert.deepEqual(await confirmRates(db, 'rateV', now), {ratesConfirmedAt: new Date(now).toISOString()});
  assert.equal((await db.collection('vendors').doc('rateV').get()).data().ratesConfirmedAt, new Date(now).toISOString());
  assert.equal((await db.collection('shops').doc('rateShop').get()).data().ratesConfirmedAt, new Date(now).toISOString());
  await db.collection('vendors').doc('rateP').set({status: 'pending'});
  await assert.rejects(confirmRates(db, 'rateP', now), /approved/);
});

test('the daily reminder: ONE topic message to all vendors at the admin\'s hour (8 AM by default); off sends nothing', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  require('./index');
  const {sendRateReminder, reminderSettings, VENDOR_TOPIC} = require('./vendor-rates')._vendorRates;
  const db = getFirestore();
  assert.deepEqual(reminderSettings({}), {on: true, hour: 8});
  assert.deepEqual(reminderSettings({rateReminder: 'false', rateReminderHour: 19}), {on: false, hour: 19});
  assert.equal(reminderSettings({rateReminderHour: 24}).hour, 8);
  const sent = [];
  const send = async m => sent.push(m);
  const at = h => Date.parse(`2026-11-16T${String(h).padStart(2, '0')}:20:00+05:30`);
  try {
    await db.doc('settings/business').set({rateReminder: '', rateReminderHour: ''}, {merge: true});
    assert.equal(await sendRateReminder(db, at(7), send), false);
    assert.equal(await sendRateReminder(db, at(8), send), true);
    assert.equal(sent.length, 1);
    assert.equal(sent[0].topic, VENDOR_TOPIC);
    assert.equal(sent[0].data.open, 'confirmRates');
    await db.doc('settings/business').set({rateReminderHour: 18}, {merge: true});
    assert.equal(await sendRateReminder(db, at(8), send), false);
    assert.equal(await sendRateReminder(db, at(18), send), true);
    await db.doc('settings/business').set({rateReminder: 'false'}, {merge: true});
    assert.equal(await sendRateReminder(db, at(18), send), false, 'switched off');
    assert.equal(sent.length, 2);
  } finally {
    await db.doc('settings/business').set({rateReminder: '', rateReminderHour: ''}, {merge: true});
  }
});
