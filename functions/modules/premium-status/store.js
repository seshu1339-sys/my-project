'use strict';
// Premium status: one answer for the rest of the system, "is this vendor Premium now?". Premium means a running plan.
//
//   vendorPlanStatus/<uid>  read only; the Plans module writes it when a payment is verified
//   vendorPremium/<uid>     {uid, active, endsAt, updatedAt}; written only here, read by the vendor app and the rules
//
// Other modules read vendorPremium and never ask how a vendor became Premium, so plans and payments can change without touching them.
const {Timestamp} = require('firebase-admin/firestore');

const endOf = plan => plan?.endsAt?.toMillis?.() ?? 0;

/// Copies a vendor's plan end into their Premium status. No plan document means not Premium.
async function syncStatus(db, uid, plan, now = Date.now()) {
  const endsAt = endOf(plan);
  await db.collection('vendorPremium').doc(uid).set({uid, active: endsAt > now, endsAt: Timestamp.fromMillis(endsAt), updatedAt: Timestamp.fromMillis(now)});
}

/// Turns off everyone whose plan has ended. Returns how many.
async function expireStatuses(db, now = Date.now()) {
  const at = Timestamp.fromMillis(now);
  const ended = await db.collection('vendorPremium').where('active', '==', true).where('endsAt', '<=', at).get();
  const batches = [];
  for (let i = 0; i < ended.docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of ended.docs.slice(i, i + 400)) batch.update(doc.ref, {active: false, updatedAt: at});
    batches.push(batch.commit());
  }
  await Promise.all(batches);
  return ended.size;
}

module.exports = {syncStatus, expireStatuses};
