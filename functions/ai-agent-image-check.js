'use strict';
// Advisory-only image licensing check for AI-suggested content. This is
// deliberately NOT a real reverse-image-search/licensing API integration
// (that is a separate, future, paid-API decision) — it only checks whether
// the image is already a known-good asset in this app's own library, and
// otherwise returns a non-blocking "unverified" status so a human admin still
// makes the actual call before any image goes live.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const {requireAdminSession} = require('./admin-session');
const {requireModuleEnabled} = require('./ai-agent-config');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};

function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
async function requireAdmin(request) {
  if (request.auth?.token?.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  requireUser(request);
  await requireAdminSession(request.auth.uid);
}

exports.checkImageLicensing = onCall(options, async request => {
  await requireAdmin(request);
  await requireModuleEnabled('imageCheck');
  const imageUrl = String(request.data?.imageUrl || '').trim();
  if (!imageUrl) throw new HttpsError('invalid-argument', 'Provide an image URL.');

  const inLibrary = await db.collection('productImageLibrary').where('url', '==', imageUrl).limit(1).get();
  if (!inLibrary.empty) {
    return {status: 'known', notes: 'This image is already in the approved product image library.'};
  }
  const looksExternal = !imageUrl.includes('firebasestorage') && !imageUrl.includes('appspot.com');
  return {
    status: 'unverified',
    notes: looksExternal
      ? 'This image is hosted outside this app’s own storage. A human admin should confirm it is licensed for commercial use before publishing.'
      : 'This image is hosted in this app’s own storage but is not yet in the approved image library. Confirm its source before publishing.',
  };
});
