'use strict';
// Company messages module (owner, 18 Nov 2026: cost cuts part 5, ₹0, no AI): official "LOCAMARKET Team" messages to vendors, sent only
// by the admin or by staff the admin allowed (to their own vendors, never Payment / charges). Own folder, own collections
// (store.js); requires no other module. The audience is a setting, so providers and transport can come later.
//
//   sendCompanyMessage        admin / permitted staff -> {type, title, body, photo?, oldAmount?, newAmount?, startsOn?, showUntil?,
//                                                         target: {all | towns + categories | vendorCodes}} -> {id, meantFor, pushes}
//   previewCompanyMessage     admin / permitted staff -> {target} -> {count}            "This will go to N vendors"
//   editCompanyMessage        admin / its staff sender -> {id, title, body, ...}       vendors see "edited"; old words kept; no push
//   deleteCompanyMessage      admin / its staff sender -> {id}                          hidden from vendors, kept in the log
//   readCompanyMessages       vendor -> {ids}                                           opened in the inbox (counted once each)
//   saveCompanyMessageSenders admin -> {staffCodes}                                     which staff may send
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {requireRole, isAdminToken} = require('../../role-auth');
const {requireAdminSession} = require('../../admin-session');
const store = require('./store');

const options = {region: 'us-central1', maxInstances: 5, invoker: 'public'};
const fail = error => { throw new HttpsError('failed-precondition', error.message); };
const fcm = message => getMessaging().send(message);

async function adminOrStaff(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  const isAdmin = isAdminToken(request.auth.token);
  if (isAdmin) await requireAdminSession(request.auth.uid);
  try { return await store.senderOf(getFirestore(), request.auth, {isAdmin}); } catch (error) { throw new HttpsError('permission-denied', error.message); }
}

exports.sendCompanyMessage = onCall({...options, timeoutSeconds: 120, memory: '256MiB'}, async request => {
  const sender = await adminOrStaff(request);
  try { return await store.sendCompanyMessage(getFirestore(), sender, request.data || {}, {send: fcm}); } catch (error) { return fail(error); }
});
exports.previewCompanyMessage = onCall(options, async request => {
  const sender = await adminOrStaff(request);
  try { return await store.preview(getFirestore(), sender, request.data || {}); } catch (error) { return fail(error); }
});
exports.editCompanyMessage = onCall(options, async request => {
  const sender = await adminOrStaff(request);
  try { return await store.editCompanyMessage(getFirestore(), sender, request.data || {}); } catch (error) { return fail(error); }
});
exports.deleteCompanyMessage = onCall(options, async request => {
  const sender = await adminOrStaff(request);
  try { return await store.deleteCompanyMessage(getFirestore(), sender, request.data || {}); } catch (error) { return fail(error); }
});
exports.readCompanyMessages = onCall({...options, maxInstances: 10}, async request => {
  const uid = requireRole(request, ['vendor']);
  try { return await store.readCompanyMessages(getFirestore(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.saveCompanyMessageSenders = onCall(options, async request => {
  if (!request.auth || !isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
  try { return await store.saveSenders(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
