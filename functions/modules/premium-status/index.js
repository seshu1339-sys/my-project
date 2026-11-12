'use strict';
// Premium status module: keeps vendorPremium/<uid> true while the vendor's plan runs (see store.js). Nothing is called from the apps.
//
//   syncPremiumStatus    trigger  -> the Plans module wrote a vendor's plan end
//   expirePremiumStatus  schedule -> plans that ended since the last run
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
// The schedule is in functions/scheduled-jobs.js (one 15-minute and one hourly job for all).
const {task} = require('../../task');
const {getFirestore} = require('firebase-admin/firestore');
const {syncStatus, expireStatuses} = require('./store');

exports.syncPremiumStatus = onDocumentWritten({document: 'vendorPlanStatus/{uid}', region: 'asia-south1', maxInstances: 3}, async event => {
  await syncStatus(getFirestore(), event.params.uid, event.data.after.data());
});
exports.expirePremiumStatus = task(async () => {
  await expireStatuses(getFirestore());
});
