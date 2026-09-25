'use strict';
// Up to 2 shop photos per approved vendor. Each stays 'pending' until the admin approves or
// rejects it; a scheduled cleanup (functions/storage-maintenance.js) deletes anything still
// pending after 15 days. Mirrors the existing vendorApplications photo-approval shape.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {requireAdminSession} = require('./admin-session');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
async function requireAdmin(request) {
  requireUser(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
}
const SLOTS = [1, 2];
const slotFile = slot => `shopPhoto${slot}`;
const photoDocId = (uid, slot) => `${uid}_${slot}`;
async function verifyUploadedImage(path) {
  const file = getStorage().bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) throw new HttpsError('failed-precondition', 'Upload the photo before submitting it.');
  const [metadata] = await file.getMetadata();
  if (!/^image\/(jpeg|png|webp)$/.test(metadata.contentType || '') || !(Number(metadata.size) > 0)) {
    throw new HttpsError('failed-precondition', 'The uploaded file is not a valid photo.');
  }
}
// Vendor: (re-)submit one of its 2 shop-photo slots for review. The client uploads the bytes to
// Storage first (same client flow as any other vendor photo upload); this callable verifies the
// object and creates/resets the Firestore record to 'pending'.
exports.submitShopPhoto = onCall(options, async request => {
  const uid = requireUser(request);
  const {slot} = request.data || {};
  if (!SLOTS.includes(slot)) throw new HttpsError('invalid-argument', 'Choose photo slot 1 or 2.');
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (!vendor || vendor.status !== 'approved') throw new HttpsError('permission-denied', 'Your vendor application must be approved before you can add shop photos.');
  const path = `vendorShopPhotos/${uid}/${slotFile(slot)}`;
  await verifyUploadedImage(path);
  await db.collection('vendorShopPhotos').doc(photoDocId(uid, slot)).set({
    vendorId: uid, vendorName: vendor.name, shopId: vendor.shopId || '', slot, path,
    status: 'pending', submittedAt: FieldValue.serverTimestamp(),
    decidedAt: FieldValue.delete(), decisionReason: FieldValue.delete(),
  }, {merge: true});
  return {status: 'pending'};
});
// Admin: approve or reject a pending shop photo. Rejecting deletes the Storage object right away
// (nothing unapproved lingers) and leaves the record so the vendor sees why; re-uploading to the
// same slot works normally afterwards.
exports.reviewShopPhoto = onCall(options, async request => {
  await requireAdmin(request);
  const {vendorId, slot, approved, reason = ''} = request.data || {};
  if (typeof vendorId !== 'string' || !SLOTS.includes(slot) || typeof approved !== 'boolean') throw new HttpsError('invalid-argument', 'Provide the vendor, slot and decision.');
  const ref = db.collection('vendorShopPhotos').doc(photoDocId(vendorId, slot));
  const path = await db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    const data = snapshot.data();
    if (!snapshot.exists || data.status !== 'pending') throw new HttpsError('failed-precondition', 'This photo was already reviewed.');
    tx.update(ref, {status: approved ? 'approved' : 'rejected', decisionReason: String(reason).slice(0, 500), decidedAt: FieldValue.serverTimestamp()});
    return data.path;
  });
  if (!approved && path) await getStorage().bucket().file(path).delete({ignoreNotFound: true});
  return {status: approved ? 'approved' : 'rejected'};
});
