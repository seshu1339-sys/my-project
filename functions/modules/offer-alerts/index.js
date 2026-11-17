'use strict';
// Offer Alerts module ("sudden offer"): when a paid vendor's offer goes live with the alert on, customers with notifications on
// within the vendor's plan km get one push; tapping it opens the shop with the way there. Own folder, own rules
// (rules.js), own collection (vendorOfferAlerts). It reads the Vendor Offers module's documents and never imports it. Removing its one
// line from functions/index.js removes the alerts; offers keep working as before.
//
//   alertNearbyOnOffer  trigger -> a vendorOffers document was written (added, approved, run again)
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {getFirestore} = require('firebase-admin/firestore');
const {releaseAlert} = require('./store');
const {wantsAlert} = require('./rules');

exports.alertNearbyOnOffer = onDocumentWritten({document: 'vendorOffers/{offerId}', region: 'asia-south1', maxInstances: 3, timeoutSeconds: 540}, async event => {
  const after = event.data?.after?.data();
  if (!after || after.status !== 'live' || !wantsAlert(after) || after.alertClaimedAt) return;
  // The push sender of the app's other notifications (devices, no repeats, push centre counts).
  const {send} = require('../../notifications')._internal;
  await releaseAlert(getFirestore(), event.params.offerId, send);
});
