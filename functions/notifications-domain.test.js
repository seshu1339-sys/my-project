const {test} = require('node:test');
const assert = require('node:assert/strict');
const {active, priceDrop} = require('./notifications-domain');
test('price alerts compare the viewed pincode and ignore base-only drops', () => {
  assert.equal(priceDrop({price: 100, prices: {'500001': 80}}, {price: 90, prices: {'500001': 80}}, '500001'), null);
  assert.equal(priceDrop({price: 100}, {price: 100, prices: {'500001': 70}}, '500001'), 70);
  assert.equal(priceDrop({price: 100}, {price: 100}, ''), null);
  assert.equal(priceDrop({price: 100}, {price: -1}, ''), null);
  assert.equal(priceDrop({price: 100}, {price: 50, active: false}, ''), null);
});
test('offers respect start, expiry, disable and invalid schedule', () => {
  const now = Date.parse('2026-09-14T00:00:00Z');
  assert.equal(active({startsAt: '2026-09-15'}, now), false);
  assert.equal(active({endsAt: '2026-09-14'}, now), false);
  assert.equal(active({active: false}, now), false);
  assert.equal(active({startsAt: 'invalid'}, now), false);
  assert.equal(active({startsAt: '2026-09-13', endsAt: '2026-09-15'}, now), true);
});
