// Abuse reports (functions/modules/abuse-reports) and the block list (functions/block-list.js), in the emulator. No real email:
// EMAIL_DRY_RUN records it.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {report, decide, reportsToSuspend, reachesSuspension} = require('.')._abuse;
const {assertNotBlocked, contactKeys} = require('../../block-list');

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};

test('the admin number decides, 10 when not set; a restore starts the count again', () => {
  assert.equal(reportsToSuspend({}), 10);
  assert.equal(reportsToSuspend({abuseReportsToSuspend: 15}), 15);
  assert.equal(reportsToSuspend({abuseReportsToSuspend: 'x'}), 10);
  assert.equal(reachesSuspension({state: 'ok', count: 10}, 10), true);
  assert.equal(reachesSuspension({state: 'ok', count: 9}, 10), false);
  assert.equal(reachesSuspension({state: 'restored', count: 12, countAtRestore: 10}, 10), false, 'after a restore 10 new reports are needed');
  assert.equal(reachesSuspension({state: 'suspended', count: 30}, 10), false, 'already suspended');
  assert.deepEqual(contactKeys({emails: [' A@B.in ', ''], phones: ['+91 98765 43210', '12']}), ['email:a@b.in', 'phone:9876543210']);
});

test('a customer who ordered reports a shop once; at the number the vendor is suspended for now and the admin is told', emulated, async () => {
  process.env.EMAIL_DRY_RUN = 'true';
  const db = getFirestore();
  const t = `ab${Date.now()}`;
  const [vendor, shop, item] = [`${t}v`, `${t}s`, `${t}p`];
  await db.doc('settings/business').set({abuseReportsToSuspend: 2}, {merge: true});
  try {
    await db.doc(`shops/${shop}`).set({name: 'Ramu Kirana', ownerId: vendor, active: true});
    await db.doc(`vendors/${vendor}`).set({status: 'approved', shopId: shop, email: `${t}@shop.in`, phone: '9876500001'});
    await db.doc(`products/${item}`).set({name: 'Rice', ownerId: vendor, shopId: shop, active: true});
    for (const c of ['c1', 'c2']) await db.doc(`orders/${t}${c}`).set({userId: `${t}${c}`, shopIds: [shop], lines: []});

    await assert.rejects(report(db, `${t}c3`, 'user', {kind: 'shop', shopId: shop, reason: 'cheating'}), /ordered from this shop/);
    assert.deepEqual(await report(db, `${t}c1`, 'user', {kind: 'shop', shopId: shop, reason: 'cheating', details: 'Took money, gave nothing'}), {count: 1, suspended: false});
    await assert.rejects(report(db, `${t}c1`, 'user', {kind: 'shop', shopId: shop, reason: 'abuse'}), /already reported/);
    await assert.rejects(report(db, `${t}c2`, 'user', {kind: 'shop', shopId: shop, reason: 'nonsense'}), /Choose why/);
    assert.deepEqual(await report(db, `${t}c2`, 'user', {kind: 'shop', shopId: shop, reason: 'fake'}), {count: 2, suspended: true});

    assert.equal((await db.doc(`vendors/${vendor}`).get()).data().status, 'suspended');
    assert.equal((await db.doc(`products/${item}`).get()).data().active, false, 'the shop\'s items are hidden');
    assert.equal((await db.doc(`shops/${shop}`).get()).data().active, false);
    const target = (await db.doc(`abuseTargets/vendor_${vendor}`).get()).data();
    assert.equal(target.state, 'suspended');
    assert.equal(target.label, 'Ramu Kirana');
    const alerts = (await db.collection('adminAlerts').where('targetKey', '==', `vendor_${vendor}`).get()).docs.map(d => d.data());
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0].count, 2);

    // The admin restores: back as it was, and a new count starts.
    assert.deepEqual(await decide(db, 'admin1', {targetKey: `vendor_${vendor}`, action: 'restore'}), {state: 'restored'});
    assert.equal((await db.doc(`vendors/${vendor}`).get()).data().status, 'approved');
    assert.equal((await db.doc(`products/${item}`).get()).data().active, true);
    // ...or blocks for good: suspended again and the email and phone on the block list.
    const blocked = await decide(db, 'admin1', {targetKey: `vendor_${vendor}`, action: 'block'});
    assert.equal(blocked.state, 'blocked');
    assert.deepEqual(blocked.blockedKeys.sort(), [`email:${t}@shop.in`, 'phone:9876500001'].sort());
    assert.equal((await db.doc(`vendors/${vendor}`).get()).data().status, 'suspended');
    await assert.rejects(assertNotBlocked(db, {emails: [`${t.toUpperCase()}@SHOP.IN`]}), /blocked/, 'the email cannot register or sign in again');
    await assert.rejects(assertNotBlocked(db, {phones: ['+91 98765 00001']}), /blocked/);
    await assertNotBlocked(db, {emails: ['someone.else@example.com'], phones: ['9000000000']});
    for (const key of blocked.blockedKeys) await db.doc(`blockedContacts/${key}`).delete();
  } finally {
    await db.doc('settings/business').set({abuseReportsToSuspend: 10}, {merge: true});
  }
});

test('a provider is reported only by a customer who called or messaged them; a vendor reports the customer of its own order', emulated, async () => {
  const db = getFirestore();
  const t = `ap${Date.now()}`;
  await db.doc(`services/${t}l`).set({name: 'Suresh Plumber', providerId: `${t}pr`, ownerId: `${t}pr`, kind: 'service'});
  await db.doc(`providers/${t}pr`).set({status: 'approved'});
  await db.doc(`usagePersonDaily/${t}c1~2026-11-13`).set({uid: `${t}c1`, keys: {[`worker_call~${t}l`]: {event: 'worker_call', key: `${t}l`, count: 1}}});
  await assert.rejects(report(db, `${t}c9`, 'user', {kind: 'provider', listingId: `${t}l`, reason: 'no_show'}), /called or messaged/);
  assert.equal((await report(db, `${t}c1`, 'user', {kind: 'provider', listingId: `${t}l`, reason: 'no_show'})).count, 1);
  assert.equal((await db.doc(`abuseTargets/provider_${t}pr`).get()).data().label, 'Suresh Plumber');

  await db.doc(`vendors/${t}v`).set({status: 'approved', shopId: `${t}s`});
  await db.doc(`vendors/${t}w`).set({status: 'approved', shopId: `${t}other`});
  await db.doc(`orders/${t}o`).set({userId: `${t}cust`, shopIds: [`${t}s`], lines: []});
  await db.doc(`users/${t}cust`).set({name: 'Kiran'});
  await assert.rejects(report(db, `${t}w`, 'vendor', {kind: 'customer', orderId: `${t}o`, reason: 'abuse'}), /got this order/);
  assert.equal((await report(db, `${t}v`, 'vendor', {kind: 'customer', orderId: `${t}o`, reason: 'abuse'})).count, 1);
  assert.equal((await db.doc(`abuseTargets/customer_${t}cust`).get()).data().label, 'Kiran');
  await assert.rejects(report(db, `${t}cust`, 'vendor', {kind: 'shop', shopId: `${t}s`, reason: 'abuse'}), /cannot be reported here/, 'a vendor reports customers only');
});
