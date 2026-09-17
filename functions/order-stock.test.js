const {test} = require('node:test');
const assert = require('node:assert/strict');
const {reconcileCancelledOrderStock} = require('./index');
const {getFirestore} = require('firebase-admin/firestore');
const db = getFirestore();

test('cancelling an order restores stock exactly once, even if toggled again', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const product = db.collection('products').doc('stock-test-p1');
  const order = db.collection('orders').doc('stock-test-o1');
  const lines = [{productId: 'stock-test-p1', quantity: 2}];
  await product.set({name: 'Rice', active: true, stock: 5});
  await order.set({status: 'confirmed', lines});
  const cancelEvent = beforeStatus => ({
    data: {
      before: {data: () => ({status: beforeStatus, lines})},
      after: {data: () => ({status: 'cancelled', lines}), ref: order},
    },
    params: {orderId: 'stock-test-o1'},
  });
  // The real trigger only fires after Firestore already committed the status
  // change; the transaction re-reads live state, so the test must too.
  await order.update({status: 'cancelled'});
  await reconcileCancelledOrderStock.run(cancelEvent('confirmed'));
  assert.equal((await product.get()).data().stock, 7);
  assert.equal((await order.get()).data().stockRestored, true);
  // A second cancellation of the same order (e.g. confirmed -> cancelled again)
  // must not restore stock twice.
  await order.update({status: 'confirmed'});
  await order.update({status: 'cancelled'});
  await reconcileCancelledOrderStock.run(cancelEvent('confirmed'));
  assert.equal((await product.get()).data().stock, 7);
  // Re-running the exact same event a second time (delivery retry) is also a no-op.
  await reconcileCancelledOrderStock.run(cancelEvent('confirmed'));
  assert.equal((await product.get()).data().stock, 7);
});

test('cancelling ignores unrelated status changes and missing products', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const order = db.collection('orders').doc('stock-test-o2');
  const lines = [{productId: 'stock-test-missing', quantity: 3}];
  await order.set({status: 'submitted', lines});
  await order.update({status: 'confirmed'});
  await reconcileCancelledOrderStock.run({
    data: {
      before: {data: () => ({status: 'submitted', lines})},
      after: {data: () => ({status: 'confirmed', lines}), ref: order},
    },
    params: {orderId: 'stock-test-o2'},
  });
  assert.equal((await order.get()).data().stockRestored, undefined);
  await order.update({status: 'cancelled'});
  await reconcileCancelledOrderStock.run({
    data: {
      before: {data: () => ({status: 'confirmed', lines})},
      after: {data: () => ({status: 'cancelled', lines}), ref: order},
    },
    params: {orderId: 'stock-test-o2'},
  });
  assert.equal((await order.get()).data().stockRestored, true);
});
