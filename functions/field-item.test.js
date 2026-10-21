const {test} = require('node:test');
const assert = require('node:assert/strict');
const {fieldItemDetails} = require('./domain');

test('a staff item needs a real price, and may name a category', () => {
  assert.deepEqual(fieldItemDetails({name: 'Rice', price: 10, stock: 3}), {name: 'Rice', price: 10, stock: 3});
  assert.deepEqual(fieldItemDetails({name: 'Rice', price: 10, stock: 3, categoryId: 'cat-grocery'}), {name: 'Rice', price: 10, stock: 3, categoryId: 'cat-grocery'});
  assert.deepEqual(fieldItemDetails({name: 'Rice', price: 10, stock: 3, categoryId: ''}), {name: 'Rice', price: 10, stock: 3}, 'blank = no category');
  assert.throws(() => fieldItemDetails({name: 'Rice', price: 0, stock: 3}), /price/, 'a free (price 0) item must not be queued');
  assert.throws(() => fieldItemDetails({name: 'Rice', price: -1, stock: 3}), /price/);
  assert.throws(() => fieldItemDetails({name: 'Rice', price: 10, stock: 3, categoryId: 'bad id!'}), /category/);
  assert.throws(() => fieldItemDetails({name: 'Rice', price: 10, stock: 3, categoryId: 5}), /category/);
});
