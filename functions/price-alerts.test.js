const {test} = require('node:test');
const assert = require('node:assert/strict');
const ready = process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST;
const {priceAlertKey} = require('./notifications-domain');

test('price alert keys are per customer-facing price, product and pincode', () => {
  assert.equal(priceAlertKey('p1', '560001', 80), 'priceDrop:p1:560001:80');
  assert.notEqual(priceAlertKey('p1', '560001', 80), priceAlertKey('p1', '560001', 70));
  assert.notEqual(priceAlertKey('p1', '560001', 80), priceAlertKey('p1', '560002', 80));
  assert.equal(priceAlertKey('p1', '', 80), 'priceDrop:p1:any:80');
});

// Runs the real functions against the emulators. Push delivery is recorded in
// _pushDryRun instead of contacting FCM.
test('price alerts: eligibility, manual send, no duplicates, automatic on/off, admin only', {skip: !ready}, async () => {
  process.env.PUSH_DRY_RUN = 'true';
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const fns = require('./index');
  const db = getFirestore();
  // oldest first (document ids are random)
  const dry = async () => (await db.collection('_pushDryRun').get()).docs.map(d => d.data()).sort((a, b) => a.createdAt.toMillis() - b.createdAt.toMillis());
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  const pid = 'alert-p1';
  const mkUser = async (uid, email) => { try { await getAuth().createUser({uid, email}); } catch { /* already exists */ } };
  const recent = Timestamp.fromMillis(Date.now() - 86400000), old = Timestamp.fromMillis(Date.now() - 120 * 86400000);
  // ann: interested + subscribed + token; ben: subscribed but no token; cy: token but unsubscribed; dee: interest is 120 days old
  for (const [uid, email] of [['ann', 'ann@t.local'], ['ben', 'ben@t.local'], ['cy', 'cy@t.local'], ['dee', 'dee@t.local']]) await mkUser(uid, email);
  await db.collection('products').doc(pid).set({name: 'Alert Lamp', price: 100, prices: {'560001': 90}, active: true});
  const v = db.collection('products').doc(pid).collection('viewers');
  await v.doc('ann').set({pincode: '560001', lastViewedAt: recent, viewCount: 7});
  await v.doc('ben').set({pincode: '560001', lastViewedAt: recent, viewCount: 2});
  await v.doc('cy').set({pincode: '', lastViewedAt: recent, viewCount: 1});
  await v.doc('dee').set({pincode: '560001', lastViewedAt: old, viewCount: 9});
  for (const uid of ['ann', 'ben', 'cy', 'dee']) await db.collection('notificationSubscribers').doc(uid).set({enabled: uid !== 'cy'});
  for (const uid of ['ann', 'cy', 'dee']) await db.collection('users').doc(uid).collection('pushTokens').doc('tok-' + uid).set({token: 'tok-' + uid});

  // ---- who is eligible
  const audience = await fns.priceAlertAudience.run({...admin, data: {productId: pid}});
  const byUid = Object.fromEntries(audience.rows.map(r => [r.uid, r]));
  assert.deepEqual(audience.rows.map(r => r.uid)[0], 'dee');                 // sorted by views, most first
  assert.equal(byUid.ann.viewCount, 7); assert.equal(byUid.ann.email, 'ann@t.local');
  assert.equal(byUid.ann.eligible, true); assert.equal(byUid.ann.currentPrice, 90);
  assert.equal(byUid.ben.eligible, false); assert.equal(byUid.ben.tokens, 0);
  assert.equal(byUid.cy.eligible, false); assert.equal(byUid.cy.subscribed, false);
  assert.equal(byUid.dee.eligible, false); assert.equal(byUid.dee.recent, false);
  assert.equal(byUid.ann.alreadyNotified, false);

  // ---- manual send reaches only the eligible customer, once
  const first = await fns.sendPriceDropAlerts.run({...admin, data: {productId: pid}});
  assert.equal(first.sent, 1); assert.equal(first.duplicate, 0);
  let pushes = await dry(); assert.equal(pushes.length, 1); assert.equal(pushes[0].uid, 'ann');
  assert.match(pushes[0].notification.body, /Alert Lamp is now ₹90 in 560001/);
  const again = await fns.sendPriceDropAlerts.run({...admin, data: {productId: pid}});
  assert.equal(again.sent, 0); assert.equal(again.duplicate, 1);              // pressing the button twice never re-sends
  assert.equal((await dry()).length, 1);
  const afterSend = (await fns.priceAlertAudience.run({...admin, data: {productId: pid}})).rows.find(r => r.uid === 'ann');
  assert.equal(afterSend.alreadyNotified, true); assert.equal(afterSend.alertedPrice, 90); assert.equal(afterSend.alertCount, 1);

  // ---- automatic trigger: the same price is a duplicate; a new lower price alerts again
  const trigger = (before, after, id) => fns.notifyPriceDrop.run({data: {before: {data: () => before}, after: {data: () => after, ref: db.collection('products').doc(pid)}}, params: {productId: pid}, id});
  await trigger({name: 'Alert Lamp', price: 100, prices: {'560001': 95}}, {name: 'Alert Lamp', price: 100, prices: {'560001': 90}}, 'e1');
  assert.equal((await dry()).length, 1);                                       // already alerted at ₹90 (manual)
  await db.collection('products').doc(pid).update({prices: {'560001': 80}});
  await trigger({name: 'Alert Lamp', price: 100, prices: {'560001': 90}}, {name: 'Alert Lamp', price: 100, prices: {'560001': 80}, active: true}, 'e2');
  pushes = await dry(); assert.equal(pushes.length, 2); assert.match(pushes[1].notification.body, /₹80/);
  await trigger({name: 'Alert Lamp', price: 100, prices: {'560001': 90}}, {name: 'Alert Lamp', price: 100, prices: {'560001': 80}}, 'e3'); // retried delivery
  assert.equal((await dry()).length, 2);
  await trigger({name: 'Alert Lamp', price: 100, prices: {'560001': 80}}, {name: 'Alert Lamp', price: 100, prices: {'560001': 85}}, 'e4'); // increase
  assert.equal((await dry()).length, 2);
  await trigger({name: 'Alert Lamp', price: 100, prices: {'560001': 80}}, {name: 'Alert Lamp', price: 100, prices: {'560001': 80}, stock: 4}, 'e5'); // unrelated write
  assert.equal((await dry()).length, 2);

  // ---- automatic alerts can be switched off; manual sending still works
  await db.collection('settings').doc('business').set({priceDropAutoEnabled: 'false'}, {merge: true});
  await trigger({name: 'Alert Lamp', price: 100, prices: {'560001': 80}}, {name: 'Alert Lamp', price: 100, prices: {'560001': 70}}, 'e6');
  assert.equal((await dry()).length, 2);
  await db.collection('products').doc(pid).update({prices: {'560001': 70}});
  const manual = await fns.sendPriceDropAlerts.run({...admin, data: {productId: pid}});
  assert.equal(manual.sent, 1); assert.equal((await dry()).length, 3);
  await db.collection('settings').doc('business').set({priceDropAutoEnabled: 'true'}, {merge: true});

  // ---- targeting a subset, and access control
  const subset = await fns.sendPriceDropAlerts.run({...admin, data: {productId: pid, uids: ['ben']}});
  assert.equal(subset.sent, 0); assert.equal(subset.results[0].status, 'ineligible');
  await assert.rejects(() => fns.priceAlertAudience.run({data: {productId: pid}}), /Sign in/);
  await assert.rejects(() => fns.priceAlertAudience.run({auth: {uid: 'ann', token: {email_verified: true}}, data: {productId: pid}}), /Administrator/);
  await assert.rejects(() => fns.sendPriceDropAlerts.run({auth: {uid: 'ann', token: {email_verified: true}}, data: {productId: pid}}), /Administrator/);
  await assert.rejects(() => fns.sendPriceDropAlerts.run({...admin, data: {productId: 'nope'}}), /not found/i);
});
