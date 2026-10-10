const {test} = require('node:test');
const assert = require('node:assert/strict');

test('submitVerifiedReview keeps a precomputed avgRating/reviewCount on the product', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const submit = (uid, data) => fns.submitVerifiedReview.run({auth: {uid, token: {email_verified: true}}, data});

  await db.collection('products').doc('p1').set({name: 'Rated product', price: 100, active: true});
  // Two different verified-purchase customers, each with their own order
  // referencing the product, matching submitVerifiedReview's own lookup.
  for (const [uid, orderId] of [['buyer1', 'o1'], ['buyer2', 'o2']]) {
    await db.collection('orders').doc(orderId).set({userId: uid, lines: [{productId: 'p1', quantity: 1}]});
    await db.collection('verifiedPurchases').doc(`${uid}_${orderId}`).set({customerId: uid, status: 'verified', orderId});
  }

  await submit('buyer1', {productId: 'p1', name: 'Buyer One', rating: 5, text: 'Loved it'});
  let product = (await db.collection('products').doc('p1').get()).data();
  assert.equal(product.avgRating, 5, 'a single 5-star review averages to 5');
  assert.equal(product.reviewCount, 1);

  await submit('buyer2', {productId: 'p1', name: 'Buyer Two', rating: 3, text: 'It was fine'});
  product = (await db.collection('products').doc('p1').get()).data();
  assert.equal(product.avgRating, 4, 'averaging a 5 and a 3 gives 4');
  assert.equal(product.reviewCount, 2);

  // A second review attempt from the same buyer is rejected and must not
  // perturb the aggregate.
  await assert.rejects(() => submit('buyer1', {productId: 'p1', name: 'Buyer One', rating: 1, text: 'again'}), /already rated/);
  product = (await db.collection('products').doc('p1').get()).data();
  assert.equal(product.avgRating, 4);
  assert.equal(product.reviewCount, 2);

  // An unrelated, never-reviewed product has no rating fields at all, so the
  // customer UI can cleanly hide the star row rather than show zero stars.
  await db.collection('products').doc('p2').set({name: 'Unrated product', price: 50, active: true});
  const unrated = (await db.collection('products').doc('p2').get()).data();
  assert.equal(unrated.avgRating, undefined);
  assert.equal(unrated.reviewCount, undefined);
});
