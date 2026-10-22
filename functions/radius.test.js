const {test} = require('node:test');
const assert = require('node:assert/strict');
const {OPTIONS, nextRadiusOption, radiusCovers, runsTogether, areaLoad, areaFullMessage} = require('./radius');
const {promotionMatchesLocation} = require('./domain');

const circle = (id, km, lat, lng, more = {}) => ({id, radiusKm: km, radiusShopId: 's', radiusLat: lat, radiusLng: lng, ...more});
const NARSIPATNAM = [17.667, 82.612], ANAKAPALLE = [17.691, 83.003], RAJAHMUNDRY = [17.0, 81.8];

test('the radius list is fixed and an in-between radius goes to the next bigger one', () => {
  assert.deepEqual(OPTIONS, [5, 10, 25, 50, 100]);
  assert.equal(nextRadiusOption(20), 25);
  assert.equal(nextRadiusOption(25), 25);
  assert.equal(nextRadiusOption(101), null);
});

test('only customers inside the circle are reached; no radius is not affected', () => {
  const ad = circle('a', 10, ...NARSIPATNAM);
  assert.equal(radiusCovers(ad, 17.67, 82.62), true);
  assert.equal(radiusCovers(ad, ...ANAKAPALLE), false);
  assert.equal(radiusCovers(ad, undefined, undefined), false);
  assert.equal(radiusCovers({title: 'plain'}, undefined, undefined), true);
  assert.equal(radiusCovers({radiusKm: 10}, 17.6, 82.6), false, 'no centre saved');
});

test('a push or an offer list uses the same rule through promotionMatchesLocation, together with the older area rules', () => {
  const offer = circle('o', 10, ...NARSIPATNAM, {targetPincode: '531116'});
  assert.equal(promotionMatchesLocation(offer, {customerPincode: '531116', customerLatitude: 17.67, customerLongitude: 82.62}), true);
  assert.equal(promotionMatchesLocation(offer, {customerPincode: '531116', customerLatitude: ANAKAPALLE[0], customerLongitude: ANAKAPALLE[1]}), false, 'right pincode, outside the circle');
  assert.equal(promotionMatchesLocation(offer, {customerPincode: '500001', customerLatitude: 17.67, customerLongitude: 82.62}), false, 'inside the circle, wrong pincode');
  assert.equal(promotionMatchesLocation({name: 'old'}, {}), true);
});

test('maximum per area', () => {
  const a = circle('a', 25, ...NARSIPATNAM, {startsAt: '2026-11-01T00:00:00', endsAt: '2026-11-30T00:00:00'});
  const b = circle('b', 25, ...NARSIPATNAM, {startsAt: '2026-11-10T00:00:00', endsAt: '2026-12-10T00:00:00'});
  const later = circle('later', 25, ...NARSIPATNAM, {startsAt: '2026-12-15T00:00:00'});
  const elsewhere = circle('elsewhere', 5, ...RAJAHMUNDRY);
  assert.equal(runsTogether(a, b), true);
  assert.equal(runsTogether(a, later), false);
  assert.equal(areaLoad(a, [a, b, later, elsewhere]), 1);
  assert.equal(areaFullMessage(a, [b], 0), null);
  assert.equal(areaFullMessage(a, [b], 2), null);
  assert.match(areaFullMessage(a, [b], 1), /already has 1/);
  assert.equal(areaFullMessage({id: 'plain'}, [b], 1), null);
  assert.equal(areaFullMessage(a, [{...b, active: false}, {...b, id: 'c', status: 'pending'}], 1), null, 'switched off and pending ads do not count');
});
