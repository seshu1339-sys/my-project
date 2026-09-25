'use strict';
// "Special Category Exclusives": a per-vendor permission (granted by the admin, with a maximum
// active duration) that lets that one vendor publish its own one-off design/product entries
// directly, without going through the normal submitVendorChange moderation queue. Items are
// ordinary `products` documents (isExclusive:true) so they need no new customer-facing screen —
// they already appear on ShopPage/the product grid via the existing active/shopId filtering.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
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
const ARCHIVE_WINDOW_MS = 15 * 86400000;
function validName(value) {
  const name = typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
  if (name.length < 2 || name.length > 120) throw new HttpsError('invalid-argument', 'Provide a name (2-120 characters).');
  return name;
}
function validPrice(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 10000000) throw new HttpsError('invalid-argument', 'Provide a valid price.');
  return Math.round(value * 100) / 100;
}
function validImageUrl(value) {
  if (typeof value !== 'string' || !/^https?:\/\//.test(value) || value.length > 2000) throw new HttpsError('invalid-argument', 'Upload a photo first.');
  return value;
}
async function requireExclusivesVendor(uid) {
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (!vendor || vendor.status !== 'approved') throw new HttpsError('permission-denied', 'Your vendor application must be approved first.');
  if (vendor.specialCategoryExclusives !== true) throw new HttpsError('permission-denied', 'Special Category Exclusives is not enabled for your account.');
  return vendor;
}
function validDuration(days, vendor) {
  const max = Number(vendor.exclusivesMaxDurationDays);
  if (!Number.isInteger(days) || days < 1 || !(max > 0) || days > max) throw new HttpsError('invalid-argument', `Choose a duration from 1 to ${Number.isFinite(max) && max > 0 ? max : 0} days.`);
  return days;
}
// Admin: grant or revoke the permission, and set the vendor's own maximum item duration.
exports.setVendorExclusivesPermission = onCall(options, async request => {
  await requireAdmin(request);
  const {vendorId, enabled, maxDurationDays} = request.data || {};
  if (typeof vendorId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(vendorId) || typeof enabled !== 'boolean') throw new HttpsError('invalid-argument', 'Provide the vendor and whether to enable the permission.');
  const vendorRef = db.collection('vendors').doc(vendorId);
  const vendor = (await vendorRef.get()).data();
  if (!vendor) throw new HttpsError('not-found', 'Vendor not found.');
  let days = Number(maxDurationDays);
  if (enabled && (!Number.isInteger(days) || days < 1 || days > 365)) throw new HttpsError('invalid-argument', 'Set a maximum active duration from 1 to 365 days.');
  await vendorRef.update({specialCategoryExclusives: enabled, exclusivesMaxDurationDays: enabled ? days : FieldValue.delete()});
  return {specialCategoryExclusives: enabled, exclusivesMaxDurationDays: enabled ? days : null};
});
// Vendor: publish a new exclusive item immediately (the permission grant is the control point,
// so individual items are not queued for review). Photo, name, price and duration are written
// as one document so they can never drift apart.
exports.submitExclusiveItem = onCall(options, async request => {
  const uid = requireUser(request);
  const vendor = await requireExclusivesVendor(uid);
  const {name, price, imageUrl, durationDays} = request.data || {};
  const safe = {name: validName(name), price: validPrice(price), imageUrl: validImageUrl(imageUrl), days: validDuration(durationDays, vendor)};
  const ref = db.collection('products').doc();
  const expiresAt = new Date(Date.now() + safe.days * 86400000).toISOString();
  await ref.set({
    name: safe.name, price: safe.price, imageUrl: safe.imageUrl, stock: 1, kind: 'product',
    shopId: vendor.shopId || '', ownerId: uid, isExclusive: true, active: true,
    durationDays: safe.days, expiresAt,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  return {status: 'active', productId: ref.id, expiresAt};
});
// Vendor: bring an archived exclusive item back, within the 15-day archive window, on a fresh
// duration (still capped by the vendor's current maximum).
exports.reactivateExclusiveItem = onCall(options, async request => {
  const uid = requireUser(request);
  const vendor = await requireExclusivesVendor(uid);
  const {productId, durationDays} = request.data || {};
  if (typeof productId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(productId)) throw new HttpsError('invalid-argument', 'Choose an item.');
  const days = validDuration(durationDays, vendor);
  const ref = db.collection('products').doc(productId);
  const data = (await ref.get()).data();
  if (!data || data.isExclusive !== true || data.ownerId !== uid) throw new HttpsError('not-found', 'Exclusive item not found.');
  if (data.active === true) throw new HttpsError('failed-precondition', 'This item is already active.');
  const archivedAtMs = Date.parse(data.archivedAt || '');
  if (!Number.isFinite(archivedAtMs) || Date.now() - archivedAtMs > ARCHIVE_WINDOW_MS) throw new HttpsError('failed-precondition', 'The 15-day archive window for this item has passed.');
  const expiresAt = new Date(Date.now() + days * 86400000).toISOString();
  await ref.update({active: true, durationDays: days, expiresAt, archivedAt: FieldValue.delete(), notifiedExpiryAt: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp()});
  return {status: 'active', expiresAt};
});
