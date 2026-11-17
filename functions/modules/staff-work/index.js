'use strict';
// Staff Work module (owner, 13 Nov 2026): counts the updates of every vendor and provider (new items, price changes, new offers; one
// per item a day) and gives them to the staff member they are linked to; daily and monthly targets, the admin's pay slabs and the
// month's pay worked out from them; "Paid" marks with a history; the read-only ID report and the staff ranking. The staff app shows a
// staff member their own work only ("My work"), live from staffWork. Requires no other feature module. Nothing here sends money.
//
//   countItemUpdate / countServiceUpdate / countOfferUpdate / countTodaysOfferUpdate   triggers on products, services, vendorOffers,
//                                                                                       vendorTodaysOffers
//   staffWorkOverview  admin -> {month, areaId}   every staff member: ID, phone, linked people, today, month, targets, pay
//   staffRanking       admin -> {month, areaId}   the same, best first
//   idReport           admin -> {code}            VEN-... / SRV-... / STF-...: everything about that one ID, read only
//   saveStaffPayConfig admin -> {dailyTarget, monthlyTarget, slabs}     setStaffTargets admin -> {staffUid, dailyTarget, monthlyTarget, slabs}
//   markStaffPaid      admin -> {staffUid, month, paid, amount, note}
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {getFirestore} = require('firebase-admin/firestore');
const {requireRole, isAdminToken} = require('../../role-auth');
const {requireAdminSession} = require('../../admin-session');
const R = require('./rules');
const S = require('./store');

const options = {region: 'us-central1', maxInstances: 5, invoker: 'public'};
const trigger = document => ({document, region: 'asia-south1', maxInstances: 5});
const fail = error => { throw new HttpsError('failed-precondition', error.message); };

async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
  return request.auth.uid;
}

const count = update => (update ? S.recordUpdate(getFirestore(), update) : null);
const data = (event, side) => (event.data?.[side]?.exists ? event.data[side].data() : null);

exports.countItemUpdate = onDocumentWritten(trigger('products/{id}'), event => count(R.updateOfItem(event.params.id, data(event, 'before'), data(event, 'after'))));
exports.countServiceUpdate = onDocumentWritten(trigger('services/{id}'), event => count(R.updateOfItem(event.params.id, data(event, 'before'), data(event, 'after'))));
exports.countOfferUpdate = onDocumentWritten(trigger('vendorOffers/{id}'), event => count(R.updateOfOffer(event.params.id, data(event, 'before'), data(event, 'after'), 'postedAt')));
exports.countTodaysOfferUpdate = onDocumentWritten(trigger('vendorTodaysOffers/{id}'), event => count(R.updateOfOffer(event.params.id, data(event, 'before'), data(event, 'after'), 'submittedAt')));

exports.staffWorkOverview = onCall({...options, timeoutSeconds: 120}, async request => {
  await requireAdmin(request);
  try { return await S.overview(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.staffRanking = onCall({...options, timeoutSeconds: 120}, async request => {
  await requireAdmin(request);
  try { return await S.ranking(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.idReport = onCall({...options, timeoutSeconds: 120}, async request => {
  await requireAdmin(request);
  try { return await S.idReport(getFirestore(), request.data?.code); } catch (error) { return fail(error); }
});
exports.saveStaffPayConfig = onCall(options, async request => {
  await requireAdmin(request);
  try { return await S.saveConfig(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.setStaffTargets = onCall(options, async request => {
  await requireAdmin(request);
  try { return await S.saveStaffTargets(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.markStaffPaid = onCall(options, async request => {
  const uid = await requireAdmin(request);
  try { return await S.markPaid(getFirestore(), uid, request.data || {}); } catch (error) { return fail(error); }
});

exports._staffWork = {R, S};
