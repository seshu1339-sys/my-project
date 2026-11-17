'use strict';
// Plan items module (owner, 13 Nov 2026): a vendor's items when a paid plan ends or comes back. Its own folder; it reads vendorPremium
// (premium-status) and the free item number (planServiceGates/main.freeItemLimit) and imports no other module.
//
//   planItemsOnPlanChange   trigger -> vendorPremium/<uid> went from active to not active (hide all but the first items) or the other way
//                                      round (show the hidden ones again)
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {getFirestore} = require('firebase-admin/firestore');
const {hideAfterPlan, showAfterRenewal, FREE_ITEMS} = require('./store');

exports.planItemsOnPlanChange = onDocumentWritten({document: 'vendorPremium/{uid}', region: 'asia-south1', maxInstances: 3, timeoutSeconds: 300}, async event => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  const db = getFirestore();
  const uid = event.params.uid;
  if (before?.active === true && after?.active !== true) {
    const gates = (await db.collection('planServiceGates').doc('main').get()).data();
    const own = (await db.collection('vendors').doc(uid).get()).data()?.itemLimit;
    const free = [own, gates?.freeItemLimit].find(n => Number.isInteger(n) && n >= 0 && n <= 100);
    await hideAfterPlan(db, uid, free ?? FREE_ITEMS);
  } else if (before?.active !== true && after?.active === true) {
    await showAfterRenewal(db, uid);
  }
});
