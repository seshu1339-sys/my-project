const {test} = require('node:test');
const assert = require('node:assert/strict');
const {hashPin, verifyPin, quote, distanceKm, validCoordinate, paymentOptions, vendorFee} = require('./domain');
const product = {name: 'Vegetables', active: true, stock: 3, price: 100, prices: {'560001': 90}, kind: 'product', shopId: 's1'};
test('salted PIN hashes verify without retaining plaintext', () => {
  const a = hashPin('123456'), b = hashPin('123456');
  assert.notEqual(a.hash, b.hash); assert(verifyPin('123456', a)); assert(!verifyPin('654321', a)); assert(!verifyPin('123456', null));
});
test('quote uses authoritative pincode price and ignores client price', () => {
  const result = quote([{productId: 'p1', quantity: 2, price: 1}], [product], '560001'); assert.equal(result.total, 180);
});
test('quote rejects unavailable, fractional and duplicate items', () => {
  assert.throws(() => quote([{productId: 'p1', quantity: 4}], [product], '560001'));
  assert.throws(() => quote([{productId: 'p1', quantity: .5}], [product], '560001'));
  assert.throws(() => quote([{productId: 'p1', quantity: 1}, {productId: 'p1', quantity: 1}], [product, product], '560001'));
  assert.throws(() => quote([{productId: 'p1', quantity: 1}], [{...product, active: false}], '560001'));
});
test('quote rejects expired promotions and invalid prices', () => {
  assert.throws(() => quote([{productId: 'p1', quantity: 1}], [{...product, endsAt: '2020-01-01'}], '560001'));
  assert.throws(() => quote([{productId: 'p1', quantity: 1}], [{...product, price: -1}], '999999'));
});
test('quote has no delivery fee unless the business configures one', () => {
  const result = quote([{productId: 'p1', quantity: 1}], [product], '999999');
  assert.equal(result.deliveryFee, 0);
  assert.equal(result.subtotal, 100);
  assert.equal(result.total, 100);
});
test('quote applies a flat delivery fee and waives it above the free-delivery threshold', () => {
  const business = {deliveryFee: 30, freeDeliveryAbove: 500};
  const small = quote([{productId: 'p1', quantity: 1}], [product], '999999', business);
  assert.equal(small.subtotal, 100);
  assert.equal(small.deliveryFee, 30);
  assert.equal(small.total, 130);
  const large = quote([{productId: 'p1', quantity: 6}], [{...product, stock: 10}], '999999', business);
  assert.equal(large.subtotal, 600);
  assert.equal(large.deliveryFee, 0);
  assert.equal(large.total, 600);
});
test('quote ignores an invalid or non-positive delivery fee configuration', () => {
  for (const business of [{deliveryFee: -5}, {deliveryFee: 0}, {deliveryFee: 'free'}, {deliveryFee: NaN}, null, undefined]) {
    const result = quote([{productId: 'p1', quantity: 1}], [product], '999999', business);
    assert.equal(result.deliveryFee, 0);
    assert.equal(result.total, 100);
  }
});
test('shop radius helpers reject invalid coordinates and measure distance', () => {
  assert.equal(distanceKm(12.9716, 77.5946, 12.9716, 77.5946), 0);
  assert(distanceKm(0, 0, 0, 1) > 111);
  assert(validCoordinate(-90));
  assert(!validCoordinate(181));
  assert(!validCoordinate('12.9'));
});
test('payment configuration defaults to direct vendor payment and keeps platform collection opt-in', () => {
  assert.deepEqual(paymentOptions(), {direct_vendor: true, cash_on_delivery: false, platform_collected: false});
  assert.deepEqual(paymentOptions({directVendorPaymentEnabled: false, cashOnDeliveryEnabled: true, platformCollectionEnabled: true}), {direct_vendor: false, cash_on_delivery: true, platform_collected: true});
});
test('vendor fee is optional or normalized to a bounded custom amount', () => {
  assert.deepEqual(vendorFee(false, 0), {required: false, amount: 0});
  assert.deepEqual(vendorFee(true, 750.456), {required: true, amount: 750.46});
  assert.throws(() => vendorFee(true, 0));
  assert.throws(() => vendorFee(true, 10000001));
});
