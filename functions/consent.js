'use strict';
// Agreement to the Terms & Conditions and the Privacy Policy, kept on the server: who agreed, when, and to which version.
//   consentStatus  -> has this signed-in person agreed to the current version?
//   recordConsent  -> the person ticked the box in an app: remember it.
// consents/<uid> holds the latest {uid, email, version, app, acceptedAt}; consents/<uid>/log keeps every agreement. Only these functions
// write them (the rules deny every client). POLICY_VERSION is the date of the pages on locamarket.in/terms and /privacy*; when the
// pages change in a way people must agree to again, change it here and in lib/domain/consent.dart (a test keeps the two equal).
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');

const POLICY_VERSION = '2026-11-04';
const APPS = ['customer', 'vendor', 'staff'];
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};

function signedIn(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}

exports.consentStatus = onCall(options, async request => {
  const uid = signedIn(request);
  const doc = await getFirestore().collection('consents').doc(uid).get();
  return {accepted: doc.exists && doc.data().version === POLICY_VERSION, version: POLICY_VERSION};
});

exports.recordConsent = onCall(options, async request => {
  const uid = signedIn(request);
  const {app, version} = request.data || {};
  if (!APPS.includes(app)) throw new HttpsError('invalid-argument', 'Unknown app.');
  if (version !== POLICY_VERSION) throw new HttpsError('failed-precondition', 'The terms were updated. Open the app again and read them.');
  const db = getFirestore();
  const record = {uid, email: request.auth.token.email ?? '', version, app, acceptedAt: FieldValue.serverTimestamp()};
  const batch = db.batch();
  batch.set(db.collection('consents').doc(uid), record);
  batch.set(db.collection('consents').doc(uid).collection('log').doc(), record);
  await batch.commit();
  return {accepted: true, version};
});
