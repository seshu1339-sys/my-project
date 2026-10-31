const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync, readdirSync} = require('node:fs');
const {resolve} = require('node:path');
const {promotionMatchesPlace, locationTokenMatches, parseLocationList} = require('./domain');
const {placeForPincode} = require('./places');

test('the functions copy of the places files is identical to the ones the apps ship', () => {
  const names = f => readdirSync(resolve(__dirname, f)).filter(n => /^places..*.v1.json$/.test(n)).sort();
  assert.deepEqual(names('data'), names('../web/data'));
  assert.ok(names('data').length >= 37, 'the index and a file for each of the 36 states and union territories');
  for (const name of names('data')) {
    assert.equal(readFileSync(resolve(__dirname, 'data', name), 'utf8'), readFileSync(resolve(__dirname, '../web/data', name), 'utf8'), name);
  }
});

test('a pincode gives its town, district and state (head office first)', () => {
  assert.deepEqual(placeForPincode('533101'), {town: 'Rajahmundry', district: 'East Godavari', state: 'Andhra Pradesh'});
  assert.deepEqual(placeForPincode(' 520001 '), {town: 'Vijayawada', district: 'Krishna', state: 'Andhra Pradesh'});
  assert.equal(placeForPincode('500001').state, 'Telangana');
  assert.deepEqual(placeForPincode('560001'), {town: 'Bengaluru', district: 'Bengaluru Urban', state: 'Karnataka'});
  assert.deepEqual(placeForPincode('999999'), {}, 'not a pincode of the directory');
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
