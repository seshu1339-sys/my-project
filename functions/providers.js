'use strict';
// Service providers: a separate kind of account from vendors (one login is never both; a person who wants both registers twice, with
// two email addresses). A provider registers like a vendor (verified email, location on, admin approval) with a name, mobile number,
// photo, one service from the admin's list (the service types in the services collection) and their own charge per hour. Once the
// admin approves, the provider's listing is created in the services collection (never in products), with the photo made public.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {requireAdminSession} = require('./admin-session');
const {locationStamp} = require('./places');
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

const words = (value, min, max, label) => {
  const v = typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
  if (v.length < min || v.length > max) throw Error(`Provide ${label} (${min}-${max} characters).`);
  return v;
};
const coordinate = value => typeof value === 'number' && Number.isFinite(value) && value >= -180 && value <= 180;

/// A provider's hourly charge in rupees: more than 0, at most 100000, two decimals at most.
function hourlyRate(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > 100000) throw Error('Enter your charge per hour (more than 0).');
  return Math.round(value * 100) / 100;
}

/// The checked details of a provider application. Throws Error(message).
function providerApplication(data = {}) {
  const phone = typeof data.phone === 'string' ? data.phone.trim() : '';
  if (!/^\+?[0-9][0-9 -]{6,17}$/.test(phone)) throw Error('Provide a valid mobile number.');
  const pincode = typeof data.pincode === 'string' ? data.pincode.trim() : '';
  if (!/^\d{6}$/.test(pincode)) throw Error('Provide a valid six-digit pincode.');
  if (!coordinate(data.latitude) || !coordinate(data.longitude)) throw Error('Turn on your location and capture it before submitting.');
  if (typeof data.serviceTypeId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(data.serviceTypeId)) throw Error('Choose a service from the list.');
  return {
    name: words(data.name, 2, 100, 'your full name'), phone, serviceTypeId: data.serviceTypeId, hourlyRate: hourlyRate(data.hourlyRate),
    address: words(data.address, 5, 500, 'your house address'), pincode, latitude: data.latitude, longitude: data.longitude,
    ...(typeof data.gpsAddress === 'string' && data.gpsAddress.trim() ? {gpsAddress: data.gpsAddress.trim().replace(/\s+/g, ' ').slice(0, 500)} : {}),
  };
}

/// Whether an account is already a vendor account (a vendor application or record, or an admin-made Quick Add vendor account).
async function isVendorAccount(uid) {
  const [application, vendor, quick] = await Promise.all(['vendorApplications', 'vendors', 'quickAccounts'].map(c => db.collection(c).doc(uid).get()));
  return application.exists || vendor.exists || quick.data()?.role === 'vendor';
}

const photoPath = uid => `providerApplications/${uid}/photo`;
// Two decimals of a degree: about 1 km, enough for "near you" without showing where the provider lives.
const approximate = value => Math.round(value * 100) / 100;

exports.registerProvider = onCall(options, async request => {
  const uid = requireUser(request);
  let details;
  try { details = providerApplication(request.data || {}); } catch (error) { throw new HttpsError('invalid-argument', error.message); }
  if (await isVendorAccount(uid)) throw new HttpsError('failed-precondition', 'This account is a vendor account. Register as a service provider with a different email address.');
  const type = (await db.collection('services').doc(details.serviceTypeId).get()).data();
  if (!type || type.kind !== 'serviceType' || type.active === false) throw new HttpsError('invalid-argument', 'Choose a service from the list.');
  const ref = db.collection('providerApplications').doc(uid);
  const existing = await ref.get();
  if (existing.exists && existing.data().status !== 'rejected') throw new HttpsError('already-exists', 'Your service-provider application is already under review.');
  const file = getStorage().bucket().file(photoPath(uid));
  const [exists] = await file.exists();
  if (!exists) throw new HttpsError('failed-precondition', 'Upload your photo before submitting.');
  const [metadata] = await file.getMetadata();
  if (!/^image\/(jpeg|png|webp)$/.test(metadata.contentType || '') || !(Number(metadata.size) > 0)) throw new HttpsError('failed-precondition', 'Upload your photo before submitting.');
  await ref.set({
    providerId: uid, ...details, serviceName: String(type.name || ''), serviceTypeKey: String(type.typeId || details.serviceTypeId.replace(/^type-/, '')),
    photoPath: file.name, email: request.auth.token.email || null, status: 'pending',
    submittedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    decisionReason: FieldValue.delete(), decidedAt: FieldValue.delete(),
  }, {merge: true});
  return {status: 'pending'};
});

exports.approveProvider = onCall(options, async request => {
  await requireAdmin(request);
  const {providerId, approved, reason = ''} = request.data || {};
  if (typeof providerId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(providerId) || typeof approved !== 'boolean') throw new HttpsError('invalid-argument', 'Provide the provider and the decision.');
  const ref = db.collection('providerApplications').doc(providerId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError('not-found', 'Service-provider application not found.');
  const data = snapshot.data();
  if (data.status !== 'pending') throw new HttpsError('failed-precondition', 'Only a pending application can be approved or rejected.');
  if (!approved) {
    if (!String(reason).trim()) throw new HttpsError('invalid-argument', 'Give the reason for rejecting.');
    await ref.set({status: 'rejected', decisionReason: String(reason).trim().slice(0, 500), decidedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {status: 'rejected'};
  }
  // The photo becomes public with the listing (copied to catalog/, which everyone can read); the application copy stays private.
  const bucket = getStorage().bucket();
  const publicPath = `catalog/provider_${providerId}.jpg`;
  await bucket.file(data.photoPath).copy(bucket.file(publicPath));
  const imageUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(publicPath)}?alt=media`;
  const listingId = `prov-${providerId}`;
  const digits = String(data.phone || '').replace(/[^0-9]/g, '');
  const batch = db.batch();
  batch.set(db.collection('services').doc(listingId), {
    kind: 'service', providerId, ownerId: providerId, name: data.name, typeId: data.serviceTypeKey, serviceName: data.serviceName,
    description: `${data.serviceName} • ₹${data.hourlyRate} per hour`, price: data.hourlyRate, unit: 'per hour',
    // Booked by calling the provider, not through the bag.
    // The listing is public: the town and an approximate location (about 1 km) only, never the house address or the exact GPS.
    stock: 0, phone: data.phone, whatsapp: digits.length === 10 ? `91${digits}` : digits, imageUrl,
    ...locationStamp({pincode: data.pincode, latitude: approximate(data.latitude), longitude: approximate(data.longitude)}),
    active: true, order: 1000, createdAt: FieldValue.serverTimestamp(),
  });
  batch.set(db.collection('providers').doc(providerId), {
    providerId, name: data.name, status: 'approved', listingId, serviceTypeId: data.serviceTypeId, approvedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.set(ref, {status: 'approved', listingId, decisionReason: String(reason).slice(0, 500), decidedAt: FieldValue.serverTimestamp()}, {merge: true});
  await batch.commit();
  return {status: 'approved', listingId};
});

// An approved provider changes their charge per hour; the listing shows it at once.
exports.updateProviderRate = onCall(options, async request => {
  const uid = requireUser(request);
  let rate;
  try { rate = hourlyRate(request.data?.hourlyRate); } catch (error) { throw new HttpsError('invalid-argument', error.message); }
  const provider = (await db.collection('providers').doc(uid).get()).data();
  if (!provider || provider.status !== 'approved') throw new HttpsError('permission-denied', 'Your service-provider application must be approved first.');
  const application = (await db.collection('providerApplications').doc(uid).get()).data() || {};
  await db.collection('services').doc(provider.listingId).set({price: rate, description: `${application.serviceName || 'Service'} • ₹${rate} per hour`, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  await db.collection('providerApplications').doc(uid).set({hourlyRate: rate, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {hourlyRate: rate};
});

exports.providerApplication = providerApplication;
exports.isVendorAccount = isVendorAccount;
