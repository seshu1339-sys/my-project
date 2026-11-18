'use strict';
const test = require('node:test');
const assert = require('node:assert');
const {_test} = require('./image-search');

test('cleanQuery keeps up to three plain words and drops NONE', () => {
  assert.strictEqual(_test.cleanQuery('Rice.'), 'rice');
  assert.strictEqual(_test.cleanQuery('School Bag, blue, big, new'), 'school bag blue');
  assert.strictEqual(_test.cleanQuery('NONE'), '');
  assert.strictEqual(_test.cleanQuery(undefined), '');
});
test('imageType reads the first bytes', () => {
  assert.strictEqual(_test.imageType(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0]).toString('base64')), 'image/jpeg');
  assert.strictEqual(_test.imageType(Buffer.from('hello world 12345').toString('base64')), null);
});
test('photo AI is off unless the admin switched on "Camera search may use AI"', async () => {
  const db = data => ({collection: () => ({doc: () => ({get: async () => ({data: () => data})})})});
  assert.strictEqual(await _test.cameraAiAllowed(db(undefined)), false);
  assert.strictEqual(await _test.cameraAiAllowed(db({rows: []})), false);
  assert.strictEqual(await _test.cameraAiAllowed(db({aiAllowed: 'true'})), false);
  assert.strictEqual(await _test.cameraAiAllowed(db({aiAllowed: true})), true);
});
