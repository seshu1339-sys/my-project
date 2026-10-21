const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {promotionMatchesPlace, locationTokenMatches, parseLocationList} = require('./domain');
const {placeForPincode} = require('./places');

test('the functions copy of the places file is identical to the one the apps ship', () => {
  assert.equal(readFileSync(resolve(__dirname, 'data/places.v1.json'), 'utf8'), readFileSync(resolve(__dirname, '../web/data/places.v1.json'), 'utf8'));
});

test('a pincode gives its town, district and state (head office first)', () => {
  assert.deepEqual(placeForPincode('533101'), {town: 'Rajahmundry', district: 'East Godavari', state: 'Andhra Pradesh'});
  assert.deepEqual(placeForPincode(' 520001 '), {town: 'Vijayawada', district: 'Krishna', state: 'Andhra Pradesh'});
  assert.equal(placeForPincode('500001').state, 'Telangana');
  assert.deepEqual(placeForPincode('560001'), {}, 'outside AP/Telangana');
  assert.deepEqual(placeForPincode(''), {});
  assert.deepEqual(placeForPincode(undefined), {});
});

const rajahmundry = {town: 'Rajahmundry', district: 'East Godavari', state: 'Andhra Pradesh'};

test('tokens: a town, its district, its state, or the older plain town name', () => {
  const hit = token => locationTokenMatches(token, rajahmundry);
  assert.ok(hit('Rajahmundry (East Godavari)'));
  assert.ok(hit('rajahmundry (east godavari)'));
  assert.ok(hit('Rajahmundry'));
  assert.ok(!hit('Rajahmundry (Krishna)'));
  assert.ok(hit('district:East Godavari'));
  assert.ok(!hit('district:Krishna'));
  assert.ok(hit('state:Andhra Pradesh'));
  assert.ok(!hit('state:Telangana'));
  assert.ok(!hit('Vijayawada'));
  assert.ok(!hit(''));
});

test('a promotion with no locations reaches everyone; one with places only those places', () => {
  assert.ok(promotionMatchesPlace({}, rajahmundry));
  assert.ok(promotionMatchesPlace({locations: ''}, {}));
  assert.ok(promotionMatchesPlace({locations: 'Rajahmundry (East Godavari), state:Telangana'}, rajahmundry));
  assert.ok(promotionMatchesPlace({locations: 'Rajahmundry (East Godavari), state:Telangana'}, {town: 'Warangal', district: 'Warangal Urban', state: 'Telangana'}));
  assert.ok(!promotionMatchesPlace({locations: 'Rajahmundry (East Godavari)'}, placeForPincode('520001')));
  assert.ok(!promotionMatchesPlace({locations: 'Rajahmundry (East Godavari)'}, {}), 'a subscriber with no known place gets general offers only');
  assert.deepEqual(parseLocationList('A, B\nC'), ['A', 'B', 'C']);
});
