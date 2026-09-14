const {test} = require('node:test');
const assert = require('node:assert/strict');
const {hashPin, verifyPin, quote} = require('./domain');
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
