'use strict';
// Permanent, sequential, human-readable IDs for vendors, field staff and shops
// (e.g. "V-000001"), kept in NEW fields (vendorCode/staffCode/shopCode) so they
// never collide with the existing `vendorId` field on `vendors/{uid}` (which is
// just the Firebase Auth UID, and is load-bearing elsewhere — see firestore.rules
// and the complaint/verifiedPurchases routing in index.js). A document gets its
// code exactly once: the onDocumentCreated triggers below assign it the moment a
// vendor/staff/shop document is created, covering every existing creation path
// (Cloud Function or direct client write) without changing any of them, since
// Firestore fires the trigger regardless of which API created the document.
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const {requireAdminSession} = require('./admin-session');
const db = getFirestore();
const triggerOptions = {region: 'asia-south1', maxInstances: 5};
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

// Re-reads `docRef` inside the transaction and no-ops if `field` is already set, so
// redelivery of an at-least-once trigger event, or a backfill run overlapping a live
// trigger, can never assign two codes to the same document or change an existing one.
// `separator` defaults to '-' (e.g. shop codes, "SH-000001"); vendor/staff codes use
// '' so the two counters they must never share a format with still look distinct
// from each other without a shared punctuation convention ("VN00001"/"STF00001").
async function assignCodeIfMissing(docRef, field, kind, prefix, width, separator = '-') {
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(docRef);
    if (!snapshot.exists) return null;
    const existing = snapshot.data()[field];
    if (existing) return existing;
    const counterRef = db.collection('_idCounters').doc(kind);
    const counterSnapshot = await tx.get(counterRef);
    const next = (counterSnapshot.data()?.value || 0) + 1;
    const code = `${prefix}${separator}${String(next).padStart(width, '0')}`;
    tx.set(counterRef, {value: next}, {merge: true});
    tx.set(docRef, {[field]: code}, {merge: true});
    return code;
  });
}

// Vendor ("VN00001") and staff ("STF00001") codes are completely independent,
// separately-counted serial sequences — one never influences the other, and
// neither shares its counter with the pre-existing shop code below.
exports.assignVendorCode = onDocumentCreated({...triggerOptions, document: 'vendors/{uid}'}, event => assignCodeIfMissing(event.data.ref, 'vendorCode', 'vendor', 'VN', 5, ''));
exports.assignStaffCode = onDocumentCreated({...triggerOptions, document: 'fieldStaff/{uid}'}, event => assignCodeIfMissing(event.data.ref, 'staffCode', 'staff', 'STF', 5, ''));
exports.assignShopCode = onDocumentCreated({...triggerOptions, document: 'shops/{id}'}, event => assignCodeIfMissing(event.data.ref, 'shopCode', 'shop', 'SH', 6));

const BACKFILL_JOBS = [
  ['vendors', 'vendorCode', 'vendor', 'VN', 5, ''],
  ['fieldStaff', 'staffCode', 'staff', 'STF', 5, ''],
  ['shops', 'shopCode', 'shop', 'SH', 6, '-'],
];
// One-time, admin-only, idempotent backfill for records created before this feature
// shipped (a creation trigger only fires for documents created after deploy). Safe to
// call more than once: assignCodeIfMissing no-ops for any document that already has its code.
exports.backfillSequentialIds = onCall(options, async request => {
  await requireAdmin(request);
  const result = {};
  for (const [collection, field, kind, prefix, width, separator] of BACKFILL_JOBS) {
    let assigned = 0, last = null;
    for (;;) {
      let query = db.collection(collection).orderBy('__name__').limit(200);
      if (last) query = query.startAfter(last);
      const page = await query.get();
      if (page.empty) break;
      for (const doc of page.docs) {
        if (!doc.data()[field]) { await assignCodeIfMissing(doc.ref, field, kind, prefix, width, separator); assigned++; }
      }
      last = page.docs[page.docs.length - 1];
      if (page.docs.length < 200) break;
    }
    result[collection] = assigned;
  }
  return result;
});
