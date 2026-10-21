const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validateVendorChange, productChangeFields} = require('./domain');

test('a vendor can ask to hide or show a product, and nothing else through that change', () => {
  assert.deepEqual(productChangeFields.visibility, ['active']);
  assert.doesNotThrow(() => validateVendorChange('visibility', {active: false}));
  assert.doesNotThrow(() => validateVendorChange('visibility', {active: true}));
  assert.throws(() => validateVendorChange('visibility', {}), /show or hide/);
  assert.throws(() => validateVendorChange('visibility', {active: 'false'}), /true or false/);
  assert.throws(() => validateVendorChange('stock', {stock: 3, active: 1}), /true or false/);
});
