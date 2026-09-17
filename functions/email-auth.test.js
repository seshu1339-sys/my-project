const {test} = require('node:test');
const assert = require('node:assert/strict');
const {placeOrder, pinLogin, setPin} = require('./index');
test('checkout requires a verified email claim before validating an order', async () => {
  await assert.rejects(placeOrder.run({data: {}}), {code: 'unauthenticated'});
  await assert.rejects(placeOrder.run({auth: {uid: 'new', token: {email_verified: false}}, data: {}}), {code: 'permission-denied'});
  await assert.rejects(placeOrder.run({auth: {uid: 'old', token: {}}, data: {}}), {code: 'permission-denied'});
  await assert.rejects(placeOrder.run({auth: {uid: 'verified', token: {email_verified: true}}, data: {}}), {code: 'invalid-argument'});
});
test('retired SMS/PIN endpoints cannot mint login tokens', async () => {
  for (const fn of [pinLogin, setPin]) await assert.rejects(fn.run({data: {}}), {code: 'failed-precondition'});
});
