'use strict';
// Hides or shows everything of one owner (a vendor's shop, products and services, or a service provider's listing) while their account
// is suspended. Each document hidden here carries hiddenBySuspension: <owner>, so showing again only brings back what this hid.
// Used by the admin's suspension (functions/index.js setVendorSuspension) and the automatic one after reports
// (functions/modules/abuse-reports).
const {FieldValue} = require('firebase-admin/firestore');

async function setCatalogVisibility(db, ownerId, shopId, hide) {
  const found = new Map();
  const add = snapshot => snapshot.docs.forEach(doc => found.set(doc.ref.path, doc));
  for (const name of ['products', 'services']) {
    add(await db.collection(name).where('ownerId', '==', ownerId).get());
    if (typeof shopId === 'string' && shopId) add(await db.collection(name).where('shopId', '==', shopId).get());
  }
  add(await db.collection('shops').where('ownerId', '==', ownerId).get());
  let batch = db.batch(), pending = 0, changed = 0;
  for (const doc of found.values()) {
    const item = doc.data();
    if (hide) { if (item.active === false) continue; batch.update(doc.ref, {active: false, hiddenBySuspension: ownerId}); }
    else { if (item.hiddenBySuspension !== ownerId) continue; batch.update(doc.ref, {active: true, hiddenBySuspension: FieldValue.delete()}); }
    changed++;
    if (++pending === 400) { await batch.commit(); batch = db.batch(); pending = 0; }
  }
  if (pending) await batch.commit();
  return changed;
}

module.exports = {setCatalogVisibility};
