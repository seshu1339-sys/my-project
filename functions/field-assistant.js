'use strict';
// Field Assistant: staff visit vendor shops in person and submit a photo + item
// name/price/stock + the shop's GPS (an existing shop by id, or a brand-new one).
// Nothing reaches customers until an admin approves — mirrors the vendor
// onboarding shape (a status-gated `fieldStaff/{uid}` role doc, a pending-then-
// approved `fieldSubmissions` queue) but is a fully separate pipeline, reviewed
// in its own admin section, never merged with vendor moderation.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {requireAdminSession} = require('./admin-session');
const {fieldShopDetails, fieldItemDetails, validCoordinate} = require('./domain');
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

// A signed-in, verified-email user asks to become a field staff member.
// Idempotent: never downgrades an already-active/suspended record, only
// creates the initial 'pending' one — safe to call every time the app opens.
exports.requestFieldStaffAccess = onCall(options, async request => {
  const uid = requireUser(request);
  const ref = db.collection('fieldStaff').doc(uid);
  const existing = await ref.get();
  if (existing.exists) return {status: existing.data().status};
  await ref.set({
    uid, name: request.auth.token.name || '', email: request.auth.token.email || null,
    status: 'pending', requestedAt: FieldValue.serverTimestamp(),
  });
  return {status: 'pending'};
});

// Admin: approve or reject a pending field-staff request.
exports.reviewFieldStaff = onCall(options, async request => {
  await requireAdmin(request);
  const {staffUid, approved, reason = ''} = request.data || {};
  if (typeof staffUid !== 'string' || typeof approved !== 'boolean') throw new HttpsError('invalid-argument', 'Provide the staff member and decision.');
  const ref = db.collection('fieldStaff').doc(staffUid);
  const snapshot = await ref.get();
  if (!snapshot.exists || snapshot.data().status !== 'pending') throw new HttpsError('failed-precondition', 'This request was already reviewed.');
  await ref.update({status: approved ? 'active' : 'rejected', decisionReason: String(reason).slice(0, 500), decidedAt: FieldValue.serverTimestamp(), decidedBy: request.auth.uid});
  return {status: approved ? 'active' : 'rejected'};
});

// Admin: suspend or reinstate an already-approved field staff member. Suspension
// takes effect immediately since submitFieldEntry re-checks status === 'active'.
exports.setFieldStaffSuspension = onCall(options, async request => {
  await requireAdmin(request);
  const {staffUid, suspended, reason = ''} = request.data || {};
  if (typeof staffUid !== 'string' || typeof suspended !== 'boolean') throw new HttpsError('invalid-argument', 'Provide the staff member and whether to suspend or reinstate.');
  const note = String(reason).trim().slice(0, 500);
  if (suspended && note.length < 3) throw new HttpsError('invalid-argument', 'Give the staff member a reason for the suspension.');
  const ref = db.collection('fieldStaff').doc(staffUid);
  const staff = (await ref.get()).data();
  if (!staff) throw new HttpsError('not-found', 'Field staff member not found.');
  if (suspended && staff.status !== 'active') throw new HttpsError('failed-precondition', 'Only an active staff member can be suspended.');
  if (!suspended && staff.status !== 'suspended') throw new HttpsError('failed-precondition', 'This staff member is not suspended.');
  if (suspended) await ref.update({status: 'suspended', decisionReason: note, decidedAt: FieldValue.serverTimestamp(), decidedBy: request.auth.uid});
  else await ref.update({status: 'active', decisionReason: FieldValue.delete(), decidedAt: FieldValue.serverTimestamp(), decidedBy: request.auth.uid});
  return {status: suspended ? 'suspended' : 'active'};
});

async function verifyUploadedPhoto(path) {
  const file = getStorage().bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) throw new HttpsError('failed-precondition', 'Upload the item photo before submitting.');
  const [metadata] = await file.getMetadata();
  if (!/^image\/(jpeg|png|webp)$/.test(metadata.contentType || '') || !(Number(metadata.size) > 0)) {
    throw new HttpsError('failed-precondition', 'The uploaded file is not a valid photo.');
  }
}

// Field staff: submit one visit's worth of data. The client has already uploaded
// the item photo to fieldSubmissions/{uid}/{submissionId}; this callable verifies
// it, validates the shop (only when onboarding a brand-new one) and item details,
// and queues a 'pending' record. Nothing here touches products/shops directly.
exports.submitFieldEntry = onCall(options, async request => {
  const uid = requireUser(request);
  const staff = (await db.collection('fieldStaff').doc(uid).get()).data();
  if (!staff || staff.status !== 'active') throw new HttpsError('permission-denied', 'Your field staff access must be approved before you can submit entries.');
  const {shopId = '', shop, item, submissionId, visitLatitude, visitLongitude} = request.data || {};
  if (typeof shopId !== 'string') throw new HttpsError('invalid-argument', 'Invalid shop selection.');
  if (typeof submissionId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(submissionId)) throw new HttpsError('invalid-argument', 'Invalid submission id.');
  // GPS is captured on every visit, whether the shop is new or already on file —
  // it's the staff member's proof of having actually been there.
  if (!validCoordinate(visitLatitude) || !validCoordinate(visitLongitude)) throw new HttpsError('invalid-argument', "Capture the shop's GPS location before submitting.");
  let shopDetails = null;
  if (shopId === '') {
    try { shopDetails = fieldShopDetails(shop || {}); } catch (error) { throw new HttpsError('invalid-argument', error.message); }
  } else {
    const existing = await db.collection('shops').doc(shopId).get();
    if (!existing.exists) throw new HttpsError('not-found', 'Selected shop not found.');
  }
  let itemDetails;
  try { itemDetails = fieldItemDetails(item || {}); } catch (error) { throw new HttpsError('invalid-argument', error.message); }
  const photoPath = `fieldSubmissions/${uid}/${submissionId}`;
  await verifyUploadedPhoto(photoPath);
  const ref = db.collection('fieldSubmissions').doc();
  await ref.set({
    staffUid: uid, staffName: staff.name || '',
    shopId, shop: shopDetails, item: {...itemDetails, photoPath},
    visitLatitude, visitLongitude,
    status: 'pending', submittedAt: FieldValue.serverTimestamp(),
  });
  return {status: 'pending', submissionId: ref.id};
});

// Admin: approve or reject a pending field submission. Rejecting deletes the
// private Storage photo right away (nothing unapproved lingers). Approving
// creates the shop (only if it was a new one) and the product with active:true,
// copies the photo into the same public "catalog/" convention every other
// admin-uploaded product photo already uses, and stamps both docs with who
// captured them (the audit trail) before deleting the private original.
exports.reviewFieldEntry = onCall({...options, timeoutSeconds: 120}, async request => {
  await requireAdmin(request);
  const {entryId, approved, reason = ''} = request.data || {};
  if (typeof entryId !== 'string' || typeof approved !== 'boolean') throw new HttpsError('invalid-argument', 'Provide the entry and decision.');
  const ref = db.collection('fieldSubmissions').doc(entryId);
  const snapshot = await ref.get();
  if (!snapshot.exists || snapshot.data().status !== 'pending') throw new HttpsError('failed-precondition', 'This entry was already reviewed.');
  const data = snapshot.data();
  const photoPath = data.item?.photoPath;
  if (!approved) {
    await ref.update({status: 'rejected', decisionReason: String(reason).slice(0, 500), decidedAt: FieldValue.serverTimestamp(), decidedBy: request.auth.uid});
    if (photoPath) await getStorage().bucket().file(photoPath).delete({ignoreNotFound: true});
    return {status: 'rejected'};
  }
  const bucket = getStorage().bucket();
  let shopId = data.shopId;
  const batch = db.batch();
  if (!shopId) {
    const shopRef = db.collection('shops').doc();
    shopId = shopRef.id;
    batch.set(shopRef, {...data.shop, active: true, createdByStaffUid: data.staffUid, createdByStaffName: data.staffName, createdAt: FieldValue.serverTimestamp()});
  }
  const productRef = db.collection('products').doc();
  let imageUrl = '';
  if (photoPath) {
    const publicPath = `catalog/${productRef.id}.jpg`;
    await bucket.file(photoPath).copy(bucket.file(publicPath));
    imageUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(publicPath)}?alt=media`;
  }
  batch.set(productRef, {
    name: data.item.name, price: data.item.price, stock: data.item.stock, kind: 'product',
    shopId, imageUrl, active: true,
    createdByStaffUid: data.staffUid, createdByStaffName: data.staffName, createdAt: FieldValue.serverTimestamp(),
  });
  batch.update(ref, {status: 'approved', decisionReason: String(reason).slice(0, 500), decidedAt: FieldValue.serverTimestamp(), decidedBy: request.auth.uid, resolvedShopId: shopId, resolvedProductId: productRef.id});
  await batch.commit();
  if (photoPath) await bucket.file(photoPath).delete({ignoreNotFound: true});
  return {status: 'approved', shopId, productId: productRef.id};
});
