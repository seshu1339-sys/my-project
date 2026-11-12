'use strict';
const {requireRole, isAdminToken} = require('../../role-auth');
// Staff Area System module. Own folder, rules (rules.js), collections (store.js) and schedule. It reads fieldStaff, shops, the admin's
// item list and vendorOffers, and imports no other module. Removing its one line from functions/index.js removes areas, targets and the
// nightly check; staff accounts, vendors and offers keep working.
//
//   saveStaffAreaTown      admin  -> a town's radius (1, 2, 3, 5 km or another)
//   saveStaffArea          admin  -> add / edit a named area (centre + the town's radius); overlaps refused
//   deleteStaffArea        admin  -> delete a free area
//   freeStaffArea          admin  -> make a taken area free again
//   saveStaffAreaSettings  admin  -> daily target, max missed days a month, Terms & Conditions
//   reactivateAreaStaff    admin  -> reactivate a staff member the system deactivated (their area must still be free)
//   staffAreaReport        admin  -> per staff and per town, for a month
//   claimStaffArea         staff  -> take a free area the admin made, standing inside it, Terms accepted
//   previewAutoStaffArea   staff  -> a tapped centre: its block, the buildings counted in OpenStreetMap, the radius (automatic)
//   claimAutoStaffArea     staff  -> register that automatic area (radius by the server only; one area per staff member)
//   myStaffAreaToday       staff  -> my area, today's count, missed days, my area's shops
//   addStaffTodayOffer     staff  -> a rate update (Today's Offer) for a shop in my area, with a live photo within 100 m
//   removeStaffTodayOffer  staff  -> remove my own offer
//   staffAreaOnStaffChange trigger  -> a staff member approved (pending area -> booked) or not approved (area free)
//   staffAreaNightly       schedule -> yesterday's rate updates for every area, days off, missed days, stop; the last-chance warning
//                                      for today goes out now, before the day is missed (00:20 India time)
//   staffAreaLastChance    schedule -> 5 PM India time: a second reminder to those whose last chance is today and who sent nothing yet
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
// The schedule is in functions/scheduled-jobs.js (one 15-minute and one hourly job for all).
const {task} = require('../../task');
const {getFirestore} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {getStorage} = require('firebase-admin/storage');
const {requireAdminSession} = require('../../admin-session');
const S = require('./store');

const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const fail = error => { throw new HttpsError('failed-precondition', error.message); };
function requireVerified(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  return request.auth.uid;
}
async function requireAdmin(request) {
  const uid = requireVerified(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
  return uid;
}
const admin = action => onCall(options, async request => {
  const uid = await requireAdmin(request);
  try { return await action(getFirestore(), request.data || {}, uid); } catch (error) { return fail(error); }
});
// Only the email's staff login (functions/role-logins.js); approval is checked by each action (store.js).
const staff = action => onCall(options, async request => {
  const uid = requireRole(request, ['staff']);
  try { return await action(getFirestore(), uid, request.data || {}); } catch (error) { return fail(error); }
});

/// A notification to a staff member's phones (users/<uid>/pushTokens, saved by the staff app on its own when the staff member signs in).
async function pushToStaff(uid, title, body) {
  const tokens = await getFirestore().collection('users').doc(uid).collection('pushTokens').get();
  if (tokens.empty) return;
  await getMessaging().sendEachForMulticast({tokens: tokens.docs.map(d => d.data().token), notification: {title, body}, data: {type: 'staffArea'}, android: {priority: 'high'}});
}

/// How many buildings OpenStreetMap has within [radiusM] metres of a place (the free Overpass service; not Google).
async function countBuildings(lat, lng, radiusM) {
  const B = require('./blocks');
  const response = await fetch('https://overpass-api.de/api/interpreter', {
    method: 'POST',
    headers: {'content-type': 'application/x-www-form-urlencoded', 'user-agent': 'LOCAMARKET-staff-areas/1.0'},
    body: `data=${encodeURIComponent(B.overpassQuery(lat, lng, radiusM))}`,
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) throw Error('The building count is busy just now. Try again in a minute.');
  return B.parseCount(await response.json());
}

exports.saveStaffAreaTown = admin((db, data) => S.saveTown(db, data));
exports.saveStaffArea = admin((db, data) => S.saveArea(db, data));
exports.deleteStaffArea = admin((db, data) => S.deleteArea(db, data));
exports.freeStaffArea = admin((db, data) => S.freeArea(db, data));
exports.saveStaffAreaSettings = admin((db, data) => S.saveSettings(db, data));
exports.reactivateAreaStaff = admin((db, data, uid) => S.reactivate(db, data, uid));
exports.staffAreaReport = admin((db, data) => S.report(db, data));
exports.claimStaffArea = staff((db, uid, data) => S.claimArea(db, uid, data));
exports.previewAutoStaffArea = staff((db, uid, data) => S.previewAutoArea(db, uid, data, countBuildings));
exports.claimAutoStaffArea = staff((db, uid, data) => S.claimAutoArea(db, uid, data, countBuildings));
exports.myStaffAreaToday = staff((db, uid) => S.myToday(db, uid));
exports.addStaffTodayOffer = staff((db, uid, data) => S.addStaffOffer(db, getStorage().bucket(), uid, data));
exports.removeStaffTodayOffer = staff((db, uid, data) => S.removeStaffOffer(db, uid, data));

exports.staffAreaOnStaffChange = onDocumentWritten({document: 'fieldStaff/{uid}', region: 'asia-south1', maxInstances: 3}, async event => {
  await S.onStaffStatus(getFirestore(), event.params.uid, event.data?.before?.data(), event.data?.after?.data());
});
exports.staffAreaNightly = task(async () => {
  await S.nightlyCheck(getFirestore(), pushToStaff);
});
exports.staffAreaLastChance = task(async () => {
  await S.lastChanceReminder(getFirestore(), pushToStaff);
});
