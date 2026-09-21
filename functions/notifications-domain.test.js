const {test} = require('node:test');
const assert = require('node:assert/strict');
const {active, priceDrop, offerNotifiable, offerKey, offerCopy} = require('./notifications-domain');
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

test('offers notify subscribers when live, unless switched off; the ticker only when asked', () => {
  const now = Date.parse('2026-09-14T00:00:00Z');
  assert.equal(offerNotifiable({name: 'Sale', placement: 'carousel'}, now), true);
  assert.equal(offerNotifiable({name: 'Sale', placement: 'ad', notifySubscribers: 'true'}, now), true);
  assert.equal(offerNotifiable({name: 'Sale', placement: 'carousel', notifySubscribers: 'false'}, now), false);
  assert.equal(offerNotifiable({name: 'Sale', placement: 'carousel', notifySubscribers: false}, now), false);
  assert.equal(offerNotifiable({name: 'Sale', placement: 'carousel', notifySubscribers: ''}, now), true);   // blank = default
  assert.equal(offerNotifiable({name: 'SHOP LOCAL', placement: 'ticker'}, now), false);
  assert.equal(offerNotifiable({name: 'SHOP LOCAL', placement: 'ticker', notifySubscribers: 'true'}, now), true);
  assert.equal(offerNotifiable({name: 'Sale', startsAt: '2026-09-15'}, now), false);                       // not live yet
  assert.equal(offerNotifiable({name: 'Sale', endsAt: '2026-09-13'}, now), false);                         // expired
  assert.equal(offerNotifiable({name: 'Sale', active: false}, now), false);
});
test('offer keys change only when the start changes; copy is trimmed and never empty', () => {
  assert.equal(offerKey('o1', {}), 'offer:o1:initial');
  assert.equal(offerKey('o1', {startsAt: '2026-09-15'}), 'offer:o1:2026-09-15');
  assert.notEqual(offerKey('o1', {startsAt: 'a'}), offerKey('o1', {startsAt: 'b'}));
  assert.equal(offerCopy({name: 'Diwali sale', description: '20% off'}).body, 'Diwali sale - 20% off');
  assert.match(offerCopy({}).body, /new offer/i);
  assert.equal(offerCopy({name: 'x'.repeat(500)}).body.length, 180);
});
