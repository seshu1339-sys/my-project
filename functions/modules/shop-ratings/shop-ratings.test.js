// Shop and provider ratings (functions/modules/shop-ratings), in the emulator.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {rate, remove, cleanRating, raterHash} = require('.')._ratings;

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};

test('a rating is 1 to 5 stars, a name, an optional short comment, and never a phone number', () => {
  assert.deepEqual(cleanRating({stars: 4, name: '  Lakshmi  ', comment: ' Good  rice '}), {stars: 4, name: 'Lakshmi', comment: 'Good rice'});
  for (const bad of [{stars: 0, name: 'Ab'}, {stars: 6, name: 'Ab'}, {stars: 3.5, name: 'Ab'}, {stars: 3, name: 'A'}, {stars: 3, name: 'Ab', comment: 'x'.repeat(301)}]) {
    assert.throws(() => cleanRating(bad), undefined, JSON.stringify(bad));
  }
  assert.throws(() => cleanRating({stars: 5, name: 'Ravi', comment: 'call me 98765 43210'}), /phone numbers/);
  assert.notEqual(raterHash('u1'), 'u1');
  assert.equal(raterHash('u1').length, 24);
});

test('one rating per customer per shop; the average and the latest comments go on the shop; the admin removes a fake one', emulated, async () => {
  const db = getFirestore();
  const t = `rt${Date.now()}`;
  await db.doc(`shops/${t}`).set({name: 'Ramu Kirana', phone: '9000000001'});
  assert.deepEqual(await rate(db, `${t}a`, {kind: 'shop', shopId: t, stars: 5, name: 'Lakshmi', comment: 'Fresh vegetables'}), {avg: 5, count: 1});
  assert.deepEqual(await rate(db, `${t}b`, {kind: 'shop', shopId: t, stars: 2, name: 'Ravi', comment: 'Slow'}), {avg: 3.5, count: 2});
  assert.deepEqual(await rate(db, `${t}a`, {kind: 'shop', shopId: t, stars: 4, name: 'Lakshmi', comment: 'Fresh vegetables'}), {avg: 3, count: 2}, 'rating again replaces it');
  const shop = (await db.doc(`shops/${t}`).get()).data();
  assert.equal(shop.ratingAvg, 3);
  assert.equal(shop.ratingCount, 2);
  assert.deepEqual(shop.ratingRecent.map(r => r.name).sort(), ['Lakshmi', 'Ravi']);
  const docs = (await db.collection('shopRatings').where('targetKey', '==', `shop_${t}`).get()).docs;
  assert.equal(docs.length, 2);
  for (const d of docs) {
    assert.equal(JSON.stringify(d.data()).includes(`${t}a`) || JSON.stringify(d.data()).includes(`${t}b`), false, 'the customer account is not in it');
    assert.equal(d.id.includes(`${t}a`), false);
  }
  const ravi = docs.find(d => d.data().name === 'Ravi');
  assert.deepEqual(await remove(db, 'admin1', ravi.id), {avg: 4, count: 1});
  assert.equal((await db.doc(`shopRatings/${ravi.id}`).get()).data().hidden, true);
  await assert.rejects(rate(db, `${t}b`, {kind: 'shop', shopId: t, stars: 5, name: 'Ravi'}), /removed by the Support Team/, 'a removed rating is not put back by its author');
  await assert.rejects(rate(db, `${t}c`, {kind: 'shop', shopId: `${t}none`, stars: 5, name: 'Sita'}), /not found/);
});

test('a provider rating goes on every listing of the provider', emulated, async () => {
  const db = getFirestore();
  const t = `rp${Date.now()}`;
  await db.doc(`services/${t}l1`).set({name: 'Plumbing', providerId: `${t}p`});
  await db.doc(`services/${t}l2`).set({name: 'Pipes', providerId: `${t}p`});
  assert.deepEqual(await rate(db, `${t}c`, {kind: 'provider', listingId: `${t}l1`, stars: 4, name: 'Kiran'}), {avg: 4, count: 1});
  for (const id of ['l1', 'l2']) assert.equal((await db.doc(`services/${t}${id}`).get()).data().ratingAvg, 4);
});
