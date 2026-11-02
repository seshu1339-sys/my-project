'use strict';
// Premium status module: keeps vendorPremium/<uid> true while the vendor's plan runs (see store.js). Nothing is called from the apps.
//
//   syncPremiumStatus    trigger  -> the Plans module wrote a vendor's plan end
//   expirePremiumStatus  schedule -> plans that ended since the last run
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore} = require('firebase-admin/firestore');
const {syncStatus, expireStatuses} = require('./store');

exports.syncPremiumStatus = onDocumentWritten({document: 'vendorPlanStatus/{uid}', region: 'asia-south1', maxInstances: 3}, async event => {
  await syncStatus(getFirestore(), event.params.uid, event.data.after.data());
});
exports.expirePremiumStatus = onSchedule({schedule: 'every 15 minutes', region: 'asia-south1', maxInstances: 1}, async () => {
  await expireStatuses(getFirestore());
});
