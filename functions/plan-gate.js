'use strict';
// The one check the older vendor services make: does this service need a plan, and does the vendor have one running?
// It only reads two documents and imports nothing from functions/modules/plans, so that module can change or go away without touching
// the services. A service runs as it always did when its gate is off, or when the check itself cannot be read. A plan never hides a shop.
const PLAN_NEEDED = 'This service needs an active plan. You can choose one in your vendor app.';

async function planAllows(db, uid, service, now = Date.now()) {
  try {
    const gates = (await db.collection('planServiceGates').doc('main').get()).data();
    if (gates?.[service] !== true) return true;
    const status = (await db.collection('vendorPlanStatus').doc(uid).get()).data();
    return (status?.endsAt?.toMillis?.() ?? 0) > now;
  } catch (error) {
    console.warn('Plan check could not be read', error.message);
    return true;
  }
}

async function requirePlan(db, uid, service, now = Date.now()) {
  if (!(await planAllows(db, uid, service, now))) throw Error(PLAN_NEEDED);
}

module.exports = {planAllows, requirePlan, PLAN_NEEDED};
