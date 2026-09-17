const {test} = require('node:test');
const assert = require('node:assert/strict');
const {notifyOrderStatus} = require('./index');
const {getFirestore} = require('firebase-admin/firestore');
const db = getFirestore();

test('order status change notifies the one customer who placed it, safely and only once', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const order = db.collection('orders').doc('notify-test-o1');
  const claims = () => db.collection('_notificationDeliveries').get();
  await order.set({status: 'submitted', userId: 'notify-test-user'});
  const assertNoDeliveryClaims = () => claims().then(s => assert.equal(s.size, 0));
  await assertNoDeliveryClaims();
  // No enabled subscriber/tokens for this user: send() must return early
  // without throwing (no real FCM call attempted) and without claiming.
  await order.update({status: 'confirmed'});
  await notifyOrderStatus.run({
    data: {
      before: {data: () => ({status: 'submitted', userId: 'notify-test-user'})},
      after: {data: () => ({status: 'confirmed', userId: 'notify-test-user'})},
    },
    params: {orderId: 'notify-test-o1'},
    id: 'evt-1',
  });
  await assertNoDeliveryClaims();
  // Re-running the same status-unchanged transition is a no-op.
  await notifyOrderStatus.run({
    data: {
      before: {data: () => ({status: 'confirmed', userId: 'notify-test-user'})},
      after: {data: () => ({status: 'confirmed', userId: 'notify-test-user'})},
    },
    params: {orderId: 'notify-test-o1'},
    id: 'evt-2',
  });
  await assertNoDeliveryClaims();
});
