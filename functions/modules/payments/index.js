'use strict';
// Bank and SMS payment verification module. Its own files, callables and collections (see store.js). Any module can ask for a payment by
// making a paymentRequests document; plans is the only one today, and this module never imports it.
//
//   savePaymentConfig        admin    -> bank details, SMS senders and patterns
//   testPaymentSms           admin    -> what the patterns find in a sample SMS
//   reviewPayment            admin    -> approve or reject from the manual check
//   submitPaymentScreenshot  vendor   -> reads the screenshot; refuses a repeat; goes to checking or the manual check
//   smsIngest                endpoint -> the SMS forwarder; needs the SMS_INGEST_TOKEN secret
//   closePaymentChecks       schedule -> a window closed with no SMS goes to the manual check
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {defineSecret} = require('firebase-functions/params');
const {getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {requireAdminSession} = require('../../admin-session');
const {anthropic, anthropicKey} = require('../ai-core');
const {tokenMatches} = require('./rules');
const {saveConfig, testSms, ingestSms, submitScreenshot, closeChecks, reviewPayment} = require('./store');

const smsToken = defineSecret('SMS_INGEST_TOKEN');
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const fail = error => { throw new HttpsError('failed-precondition', error.message); };
function requireVerified(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
async function requireAdmin(request) {
  const uid = requireVerified(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
}

exports.savePaymentConfig = onCall(options, async request => {
  await requireAdmin(request);
  try { return await saveConfig(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.testPaymentSms = onCall(options, async request => {
  await requireAdmin(request);
  try { return await testSms(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.reviewPayment = onCall(options, async request => {
  await requireAdmin(request);
  try { return await reviewPayment(getFirestore(), getStorage().bucket(), request.data || {}); } catch (error) { return fail(error); }
});
exports.submitPaymentScreenshot = onCall({...options, secrets: [anthropicKey], timeoutSeconds: 120, memory: '512MiB'}, async request => {
  const uid = requireVerified(request);
  try { return await submitScreenshot(getFirestore(), getStorage().bucket(), anthropic, uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.smsIngest = onRequest({region: 'asia-south1', maxInstances: 3, invoker: 'public', secrets: [smsToken]}, async (req, res) => {
  if (req.method !== 'POST') return void res.status(405).send('POST only');
  if (!tokenMatches(req.get('authorization') ?? '', smsToken.value())) return void res.status(401).send('Unauthorized');
  try {
    const result = await ingestSms(getFirestore(), getStorage().bucket(), req.body ?? {});
    res.json(result);
  } catch (error) {
    // Never the SMS text in a log.
    console.error('SMS not stored', error.code ?? 'unknown');
    res.status(500).send('Try again');
  }
});
exports.closePaymentChecks = onSchedule({schedule: 'every 15 minutes', region: 'asia-south1', maxInstances: 1}, async () => {
  await closeChecks(getFirestore());
});
