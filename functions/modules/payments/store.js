'use strict';
// What the payment module reads and writes. It knows nothing about plans: paymentRequests is the only meeting point.
//
//   paymentBankConfig/main          admin only: bank details, SMS senders and patterns, window, limits
//   paymentBankPublic/main          what vendors see: {ready, accountName, accountNumber, ifsc, upiId}
//   paymentRequests/<id>            made by the asking module; status: awaiting_payment -> checking -> verified, or -> manual_review ->
//                                   verified | rejected. On verified this module adds paidAt, which is all the asking module needs.
//   paymentIds/<paymentId>          one per payment id ever claimed, created in a transaction: this is the UNIQUE rule
//   paymentScreenshotHashes/<sha>   one per screenshot ever sent: the same photo twice is refused before any AI call
//   paymentSms/<paymentId>          {paymentId, amount, smsAt, used}. Never the SMS text.
const crypto = require('node:crypto');
const {Timestamp} = require('firebase-admin/firestore');
const {takeDailyUse, logAiCall, SONNET} = require('../ai-core');
const {extractClaim} = require('./extract');
const {DEFAULT_CONFIG, HOUR_MS, configReady, validateConfig, publicDetails, senderAllowed, paymentIdValid, parseSms, claimProblem, smsConfirms, istMillis} = require('./rules');

const FOLDER = 'paymentScreenshots';
const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const MAX_BYTES = 5 * 1024 * 1024;
const ID = /^[a-zA-Z0-9_-]{1,128}$/;

const requests = db => db.collection('paymentRequests');
const stamp = ms => Timestamp.fromMillis(ms);

async function readConfig(db) {
  return {...DEFAULT_CONFIG, ...(await db.collection('paymentBankConfig').doc('main').get()).data()};
}

/// The admin saves the bank details. Vendors get only the public part.
async function saveConfig(db, data, now = Date.now()) {
  const config = validateConfig(data);
  const batch = db.batch();
  batch.set(db.collection('paymentBankConfig').doc('main'), {...config, updatedAt: stamp(now)});
  batch.set(db.collection('paymentBankPublic').doc('main'), {...publicDetails(config), updatedAt: stamp(now)});
  await batch.commit();
  return {ready: configReady(config)};
}

/// The admin's test box: what the saved patterns find in a sample SMS. Nothing is stored.
async function testSms(db, data) {
  const config = await readConfig(db);
  return {senderAllowed: senderAllowed(data.sender, config), found: parseSms(data.text, config)};
}

async function notify(db, uid, title, body, now) {
  await db.collection('vendorNotices').add({vendorId: uid, type: 'payment', title, body, createdAt: stamp(now)});
}

async function dropScreenshot(bucket, path) {
  if (path) await bucket.file(path).delete({ignoreNotFound: true});
}

async function toManualCheck(db, requestId, reason, extra, now) {
  await requests(db).doc(requestId).update({status: 'manual_review', reviewReason: reason, ...extra, updatedAt: stamp(now)});
}

/// Verifies a request in checking if its SMS is in. Runs once, from whichever of the SMS and the screenshot arrives last.
async function tryMatch(db, bucket, paymentId, config, now) {
  const owner = (await db.collection('paymentIds').doc(paymentId).get()).data();
  if (!owner) return false;
  const requestRef = requests(db).doc(owner.requestId);
  const smsRef = db.collection('paymentSms').doc(paymentId);
  const outcome = await db.runTransaction(async tx => {
    const [requestDoc, smsDoc] = [await tx.get(requestRef), await tx.get(smsRef)];
    const request = requestDoc.data(), sms = smsDoc.data();
    if (request?.status !== 'checking' || !sms || sms.used) return null;
    const smsAt = sms.smsAt.toMillis();
    if (!smsConfirms({amount: sms.amount, smsAt}, request.claimedPaidAt.toMillis(), request.amount, config.windowHours)) {
      tx.update(requestRef, {status: 'manual_review', reviewReason: 'The bank SMS does not match the amount or time.', updatedAt: stamp(now)});
      return {verified: false, request};
    }
    tx.update(smsRef, {used: true, requestId: owner.requestId});
    tx.update(requestRef, {status: 'verified', paidAt: stamp(Math.min(smsAt, now)), verifiedBy: 'sms', updatedAt: stamp(now)});
    return {verified: true, request};
  });
  if (outcome?.verified) await dropScreenshot(bucket, outcome.request.screenshotPath);
  return outcome?.verified === true;
}

/// The SMS endpoint: keeps a credit SMS from the bank, by id and amount only, and matches it. Anything else is dropped unread.
async function ingestSms(db, bucket, data, now = Date.now()) {
  const config = await readConfig(db);
  if (!configReady(config) || !senderAllowed(data.sender, config)) return {stored: false};
  const found = parseSms(data.text, config);
  if (!found) return {stored: false};
  const sent = Number(data.receivedAt);
  const smsAt = Number.isFinite(sent) && sent > 0 && sent <= now ? sent : now;
  try {
    await db.collection('paymentSms').doc(found.paymentId).create({...found, smsAt: stamp(smsAt), used: false});
  } catch (error) {
    if (error.code !== 6) throw error; // 6: already there, the forwarder sent it twice
  }
  await tryMatch(db, bucket, found.paymentId, config, now);
  return {stored: true};
}

/// Claims a payment id for a request. False when any request ever used it. This transaction is what makes the id unique.
async function claimPaymentId(db, paymentId, requestId, uid, now) {
  const ref = db.collection('paymentIds').doc(paymentId);
  return db.runTransaction(async tx => {
    if ((await tx.get(ref)).exists) return false;
    tx.create(ref, {requestId, uid, createdAt: stamp(now)});
    return true;
  });
}

/// Keeps the hash of a screenshot. False when the same photo was already sent.
async function claimHash(db, hash, uid, now) {
  const ref = db.collection('paymentScreenshotHashes').doc(hash);
  return db.runTransaction(async tx => {
    if ((await tx.get(ref)).exists) return false;
    tx.create(ref, {uid, createdAt: stamp(now)});
    return true;
  });
}

/// Reads the screenshot with AI. No key, an API failure or a refusal all mean the admin looks at it instead.
async function readScreenshot(db, client, bytes, contentType, uid, now) {
  try {
    const {claim, response} = await extractClaim(client(), bytes, contentType);
    await logAiCall(db, {feature: 'payment-screenshot', model: SONNET, usage: response.usage, uid, stopReason: response.stop_reason}, now);
    return claim;
  } catch (error) {
    console.warn('Screenshot not read', error.status ?? error.message);
    return null;
  }
}

/// A vendor sends the screenshot of a request. Refused outright for a repeat; otherwise it goes to SMS checking or the admin's manual check.
async function submitScreenshot(db, bucket, client, uid, data, now = Date.now()) {
  const {requestId, path} = data;
  if (typeof requestId !== 'string' || !ID.test(requestId)) throw new Error('Payment not found.');
  const request = (await requests(db).doc(requestId).get()).data();
  if (request?.uid !== uid) throw new Error('Payment not found.');
  if (request.status !== 'awaiting_payment') throw new Error('This payment is already being checked.');
  const config = await readConfig(db);
  if (!configReady(config)) throw new Error('Payments are not open yet.');
  if (typeof path !== 'string' || !path.startsWith(`${FOLDER}/${uid}/`) || path.includes('..')) throw new Error('Upload the screenshot from your own vendor app.');
  const file = bucket.file(path);
  const [exists] = await file.exists();
  if (!exists) throw new Error('The screenshot was not found. Upload it again.');
  const [metadata] = await file.getMetadata();
  if (!IMAGE_TYPES.includes(metadata.contentType) || Number(metadata.size) > MAX_BYTES) { await dropScreenshot(bucket, path); throw new Error('Send a JPG, PNG or WebP image under 5 MB.'); }
  if (!(await takeDailyUse(db, `payment-screenshot-${uid}`, config.dailyScreenshots, now))) { await dropScreenshot(bucket, path); throw new Error('Too many screenshots today. Try again tomorrow.'); }
  const [bytes] = await file.download();
  const hash = crypto.createHash('sha256').update(bytes).digest('hex');
  if (!(await claimHash(db, hash, uid, now))) { await dropScreenshot(bucket, path); throw new Error('This screenshot was already used.'); }

  const claim = await readScreenshot(db, client, bytes, metadata.contentType, uid, now);
  const seen = {screenshotPath: path, ...(claim ? {claimedId: claim.paymentId, claimedAmount: claim.amount, claimedDate: claim.date, claimedTime: claim.time} : {})};
  const problem = claimProblem(claim, request, config.windowHours, now);
  if (problem) {
    await toManualCheck(db, requestId, problem, seen, now);
    return {status: 'manual_review'};
  }
  if (!(await claimPaymentId(db, claim.paymentId, requestId, uid, now))) { await dropScreenshot(bucket, path); throw new Error('This payment ID was already used.'); }
  const claimedPaidAt = istMillis(claim.date, claim.time);
  await requests(db).doc(requestId).update({
    ...seen, status: 'checking', paymentId: claim.paymentId, claimedPaidAt: stamp(claimedPaidAt), checkUntil: stamp(now + config.windowHours * HOUR_MS), updatedAt: stamp(now),
  });
  const verified = await tryMatch(db, bucket, claim.paymentId, config, now);
  return {status: verified ? 'verified' : 'checking'};
}

/// The window closed with no matching SMS: the admin decides.
async function closeChecks(db, now = Date.now()) {
  const late = await requests(db).where('status', '==', 'checking').where('checkUntil', '<=', stamp(now)).get();
  for (const doc of late.docs) await toManualCheck(db, doc.id, 'No bank SMS came in time.', {}, now);
  return late.size;
}

/// The admin decides a request in the manual check. Only this, or a matching SMS, ever verifies a payment.
async function reviewPayment(db, bucket, data, now = Date.now()) {
  const {requestId, action} = data;
  if (typeof requestId !== 'string' || !ID.test(requestId)) throw new Error('Payment not found.');
  if (action !== 'approve' && action !== 'reject') throw new Error('Choose approve or reject.');
  const ref = requests(db).doc(requestId);
  const request = (await ref.get()).data();
  if (request?.status !== 'manual_review' && request?.status !== 'checking') throw new Error('This payment is not waiting for a check.');
  if (action === 'reject') {
    await ref.update({status: 'rejected', updatedAt: stamp(now)});
    await notify(db, request.uid, 'Your payment was not accepted', 'The office could not confirm your payment. Please contact the office.', now);
  } else {
    // A claim that went straight to the manual check has not taken its payment id yet; an id stays unique even when the admin approves.
    const paymentId = request.paymentId ?? (paymentIdValid(request.claimedId) ? request.claimedId : null);
    if (paymentId && !request.paymentId && !(await claimPaymentId(db, paymentId, requestId, request.uid, now))) throw new Error('This payment ID was already used by another payment.');
    const claimed = request.claimedPaidAt?.toMillis?.() ?? istMillis(request.claimedDate, request.claimedTime) ?? now;
    await ref.update({status: 'verified', paidAt: stamp(Math.min(claimed, now)), verifiedBy: 'admin', ...(paymentId ? {paymentId} : {}), updatedAt: stamp(now)});
    if (paymentId && (await db.collection('paymentSms').doc(paymentId).get()).exists) await db.collection('paymentSms').doc(paymentId).update({used: true, requestId});
  }
  await dropScreenshot(bucket, request.screenshotPath);
  return {status: action === 'approve' ? 'verified' : 'rejected'};
}

module.exports = {readConfig, saveConfig, testSms, ingestSms, submitScreenshot, closeChecks, reviewPayment, FOLDER};
