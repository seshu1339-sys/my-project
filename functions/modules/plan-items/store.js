'use strict';
// Plan items module: what happens to a vendor's items when a paid plan ends or comes back (owner, 13 Nov 2026).
//   vendorPremium/<uid>   read only (premium-status module keeps it)
//   products/<id>         active, hiddenByPlan: true on the items this module hid; createdAt (when the vendor posted it)
// The first [keep] items the vendor posted stay live when the plan ends; the others are hidden, never deleted. When the vendor has a
// running plan again, exactly the items this module hid are shown again. An item the admin or the vendor hid themselves is left alone.
const {FieldValue, Timestamp} = require('firebase-admin/firestore');

const FREE_ITEMS = 2;
const created = doc => doc.data().createdAt?.toMillis?.() ?? doc.data().updatedAt?.toMillis?.() ?? 0;
const oldestFirst = (a, b) => created(a) - created(b) || a.id.localeCompare(b.id);

async function chunked(db, docs, change) {
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + 400)) batch.update(doc.ref, change);
    await batch.commit();
  }
}

/// The plan ended: hide the items after the first [keep]. Returns how many were hidden.
async function hideAfterPlan(db, uid, keep = FREE_ITEMS, now = Date.now()) {
  const items = (await db.collection('products').where('ownerId', '==', uid).get()).docs.sort(oldestFirst);
  const extra = items.slice(Math.max(0, keep)).filter(doc => doc.data().active !== false);
  await chunked(db, extra, {active: false, hiddenByPlan: true, updatedAt: Timestamp.fromMillis(now)});
  return extra.length;
}

/// A plan runs again: show the items that were hidden because the plan ended. Returns how many came back.
async function showAfterRenewal(db, uid, now = Date.now()) {
  const hidden = (await db.collection('products').where('ownerId', '==', uid).where('hiddenByPlan', '==', true).get()).docs;
  const back = hidden.filter(doc => doc.data().awaitingOwnPhoto !== true);
  await chunked(db, back, {active: true, hiddenByPlan: FieldValue.delete(), updatedAt: Timestamp.fromMillis(now)});
  // An item still waiting for its own photo stays hidden, but is no longer the plan's to bring back.
  await chunked(db, hidden.filter(doc => doc.data().awaitingOwnPhoto === true), {hiddenByPlan: FieldValue.delete()});
  return back.length;
}

module.exports = {hideAfterPlan, showAfterRenewal, FREE_ITEMS};
