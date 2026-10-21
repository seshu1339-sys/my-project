'use strict';
// Quick Add Item. Staff (any town in the pincode directory) and Vendors (their own shop, locked by GPS)
// add short-lived items from a phone: photo, rate, category, start time and how long to show it.
// Every item waits as 'pending' for the admin; only an approved item is public, and only between
// startsAt and expiresAt (the clock starts at the later of approval and the requested start).
// Expired items are hidden, never deleted. All writes go through these callables.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {getAuth} = require('firebase-admin/auth');
const {requireAdminSession} = require('./admin-session');
const {quickItemDetails, approvedWindow, dailyLimit, dayKey} = require('./quick-domain');
const {nearestPlace, findPlace} = require('./places');
const {distanceKm} = require('./domain');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
// A vendor may add items only while standing at their own shop: within this many metres of it.
const SHOP_RADIUS_M = 100;
const MAX_BATCH = 5;

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
const clean = (value, max) => (typeof value === 'string' ? value.trim().slice(0, max) : '');

// ---- accounts ------------------------------------------------------------------------------
async function nextCode(kind, prefix) {
  return db.runTransaction(async tx => {
    const ref = db.collection('_idCounters').doc(kind);
    const next = ((await tx.get(ref)).data()?.value || 0) + 1;
    tx.set(ref, {value: next}, {merge: true});
    return `${prefix}${String(next).padStart(3, '0')}`;
  });
}

/// Admin adds a Staff or Vendor: name, phone, email, photo. The person gets an automatic code
/// (ST001.. / VN001..) and a password-reset link to set their own password -- no password is ever
/// chosen or shared by the admin. A vendor's shop location is NOT typed in: the vendor takes GPS
/// at the shop (setQuickShopLocation) and the nearest town and pincode are found automatically.
exports.createQuickAccount = onCall(options, async request => {
  await requireAdmin(request);
  const {role, name, phone, email, photoUrl = '', shopName = ''} = request.data || {};
  if (!['staff', 'vendor'].includes(role)) throw new HttpsError('invalid-argument', 'Choose Staff or Vendor.');
  const cleanName = clean(name, 100), cleanPhone = clean(phone, 20), cleanEmail = clean(email, 200).toLowerCase();
  if (cleanName.length < 2) throw new HttpsError('invalid-argument', 'Enter the name.');
  if (!/^\+?[0-9][0-9 -]{6,17}$/.test(cleanPhone)) throw new HttpsError('invalid-argument', 'Enter a valid phone number.');
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cleanEmail)) throw new HttpsError('invalid-argument', 'Enter a valid email address.');
  const photo = clean(photoUrl, 1000);
  if (!/^https:\/\//.test(photo)) throw new HttpsError('invalid-argument', 'Add the person\'s photo.');
  const auth = getAuth();
  let user;
  try { user = await auth.getUserByEmail(cleanEmail); }
  catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    user = await auth.createUser({email: cleanEmail, displayName: cleanName, emailVerified: true});
  }
  if ((await db.collection('quickAccounts').doc(user.uid).get()).exists) throw new HttpsError('already-exists', 'This email already has a Quick Add account.');
  if (!user.emailVerified) await auth.updateUser(user.uid, {emailVerified: true});
  const code = await nextCode(role === 'staff' ? 'quickStaff' : 'quickVendor', role === 'staff' ? 'ST' : 'VN');
  await db.collection('quickAccounts').doc(user.uid).set({
    uid: user.uid, role, code, name: cleanName, phone: cleanPhone, email: cleanEmail, photoUrl: photo,
    shopLocked: false, shopName: role === 'vendor' ? clean(shopName, 120) || cleanName : '',
    active: true, createdAt: FieldValue.serverTimestamp(), createdBy: request.auth.uid,
  });
  const resetLink = await auth.generatePasswordResetLink(cleanEmail);
  return {uid: user.uid, code, resetLink};
});

/// Admin: change an account's details, or unlock a vendor's shop location so it can be set again.
exports.updateQuickAccount = onCall(options, async request => {
  await requireAdmin(request);
  const {uid, name, phone, photoUrl, resetShopLocation} = request.data || {};
  const ref = db.collection('quickAccounts').doc(String(uid || ''));
  const account = await ref.get();
  if (!account.exists) throw new HttpsError('not-found', 'Account not found.');
  const patch = {};
  if (name !== undefined) { if (clean(name, 100).length < 2) throw new HttpsError('invalid-argument', 'Enter the name.'); patch.name = clean(name, 100); }
  if (phone !== undefined) { if (!/^\+?[0-9][0-9 -]{6,17}$/.test(clean(phone, 20))) throw new HttpsError('invalid-argument', 'Enter a valid phone number.'); patch.phone = clean(phone, 20); }
  if (photoUrl !== undefined) { if (!/^https:\/\//.test(clean(photoUrl, 1000))) throw new HttpsError('invalid-argument', 'Add the person\'s photo.'); patch.photoUrl = clean(photoUrl, 1000); }
  if (resetShopLocation === true && account.data().role === 'vendor') {
    Object.assign(patch, {
      shopLocked: false, shopLatitude: FieldValue.delete(), shopLongitude: FieldValue.delete(), shopLockedAt: FieldValue.delete(),
      locationName: FieldValue.delete(), locationTown: FieldValue.delete(), locationDistrict: FieldValue.delete(), locationState: FieldValue.delete(), locationPincode: FieldValue.delete(),
    });
  }
  await ref.update({...patch, updatedAt: FieldValue.serverTimestamp()});
  return {updated: Object.keys(patch)};
});

exports.setQuickAccountActive = onCall(options, async request => {
  await requireAdmin(request);
  const {uid, active} = request.data || {};
  if (typeof uid !== 'string' || typeof active !== 'boolean') throw new HttpsError('invalid-argument', 'Provide the account and Active/Inactive.');
  const ref = db.collection('quickAccounts').doc(uid);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', 'Account not found.');
  await ref.update({active, statusChangedAt: FieldValue.serverTimestamp(), statusChangedBy: request.auth.uid});
  return {active};
});

async function activeAccount(uid) {
  const account = (await db.collection('quickAccounts').doc(uid).get()).data();
  if (!account) throw new HttpsError('permission-denied', 'Quick Add is not set up for your account. Contact admin.');
  if (account.active !== true) throw new HttpsError('permission-denied', 'Your account is inactive, contact admin.');
  return account;
}

async function verifyUploadedPhoto(path) {
  const file = getStorage().bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) throw new HttpsError('failed-precondition', 'Take or choose the item photo first.');
  const [metadata] = await file.getMetadata();
  if (!/^image\/(jpeg|png|webp)$/.test(metadata.contentType || '') || !(Number(metadata.size) > 0)) throw new HttpsError('failed-precondition', 'The uploaded file is not a valid photo.');
}

// ---- where an item is ----------------------------------------------------------------------
const validCoordinate = value => typeof value === 'number' && Number.isFinite(value);
const placeFields = place => ({locationId: '', locationName: place.town, locationTown: place.town, locationDistrict: place.district, locationState: place.state, locationPincode: place.pincode});

/// A vendor takes GPS at the shop once; the nearest town and pincode come from the pincode directory
/// and are then locked for good (only the admin can unlock it).
exports.setQuickShopLocation = onCall(options, async request => {
  const uid = requireUser(request);
  const account = await activeAccount(uid);
  if (account.role !== 'vendor') throw new HttpsError('permission-denied', 'Only vendors have a shop location.');
  if (account.shopLocked === true) throw new HttpsError('failed-precondition', 'Your shop location is already set and cannot be changed. Contact admin.');
  const {latitude, longitude} = request.data || {};
  if (!validCoordinate(latitude) || !validCoordinate(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) throw new HttpsError('invalid-argument', 'Could not read your location. Turn on GPS and try again.');
  const place = nearestPlace(latitude, longitude);
  if (!place) throw new HttpsError('failed-precondition', 'Your shop is outside Andhra Pradesh and Telangana, so a town could not be found.');
  await db.collection('quickAccounts').doc(uid).update({
    ...placeFields(place), shopLatitude: latitude, shopLongitude: longitude, shopLocked: true, shopLockedAt: FieldValue.serverTimestamp(),
  });
  return {town: place.town, district: place.district, state: place.state, pincode: place.pincode};
});

/// A vendor adds, edits or re-activates items only within SHOP_RADIUS_M of their locked shop.
function requireAtShop(account, data) {
  if (account.role !== 'vendor') return;
  if (account.shopLocked !== true) throw new HttpsError('failed-precondition', 'Set your shop location first (at your shop).');
  const {latitude, longitude} = data || {};
  if (!validCoordinate(latitude) || !validCoordinate(longitude)) throw new HttpsError('failed-precondition', 'Could not read your location. Turn on GPS and try again.');
  const metres = distanceKm(latitude, longitude, account.shopLatitude, account.shopLongitude) * 1000;
  if (metres > SHOP_RADIUS_M) throw new HttpsError('permission-denied', 'మీరు మీ షాప్ దగ్గర లేరు (You are not near your shop).');
}

async function resolveLocation(account, data = {}) {
  // A vendor's place is the one locked at registration; asking for another one is refused.
  if (account.role === 'vendor') {
    if (data.locationTown && String(data.locationTown).trim().toLowerCase() !== String(account.locationTown || '').toLowerCase()) throw new HttpsError('permission-denied', 'Your shop location is fixed and cannot be changed.');
    return {locationId: '', locationName: account.locationName, locationTown: account.locationTown, locationDistrict: account.locationDistrict, locationState: account.locationState, locationPincode: account.locationPincode};
  }
  // Staff: a town from the pincode directory (found automatically from GPS, or searched) ...
  if (data.locationTown !== undefined || data.locationPincode !== undefined) {
    const place = findPlace({town: data.locationTown, district: data.locationDistrict, pincode: data.locationPincode});
    if (!place) throw new HttpsError('invalid-argument', 'Choose a town from the list.');
    return placeFields(place);
  }
  // ... or one of the extra places the admin added.
  const id = data.locationId;
  if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(id)) throw new HttpsError('invalid-argument', 'Choose a location from the list.');
  const found = await db.collection('locations').doc(id).get();
  if (!found.exists || found.data().active === false) throw new HttpsError('invalid-argument', 'Choose a location from the list.');
  const name = found.data().name || found.id;
  return {locationId: found.id, locationName: name, locationTown: found.data().town || name, locationDistrict: found.data().district || '', locationState: '', locationPincode: String(found.data().pincode || '')};
}

function parseDetails(data, now) {
  try { return quickItemDetails(data, now); } catch (error) { throw new HttpsError('invalid-argument', error.message); }
}

const ownerFields = (uid, account) => ({ownerUid: uid, ownerRole: account.role, ownerCode: account.code, ownerName: account.name, ownerPhone: account.phone || '', shopName: account.shopName || ''});
const capturedFields = data => (validCoordinate(data?.latitude) && validCoordinate(data?.longitude) ? {capturedLatitude: data.latitude, capturedLongitude: data.longitude} : {});
const resetFields = () => ({status: 'pending', decisionReason: FieldValue.delete(), startsAt: FieldValue.delete(), expiresAt: FieldValue.delete(), approvedAt: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp()});

async function categoryFor(categoryId) {
  const category = await db.collection('categories').doc(categoryId).get();
  if (!category.exists) throw new HttpsError('invalid-argument', 'Choose a valid category.');
  return category.data();
}

/// Save a new item (no itemId) or edit one of your own (itemId). Either way the item then waits
/// for the admin. Only a NEW item counts toward the daily limit. A vendor must be at their shop.
exports.saveQuickItem = onCall(options, async request => {
  const uid = requireUser(request);
  const account = await activeAccount(uid);
  const now = Date.now();
  const {itemId, submissionId} = request.data || {};
  const details = parseDetails(request.data, now);
  const category = await categoryFor(details.categoryId);
  requireAtShop(account, request.data);
  const location = await resolveLocation(account, request.data);
  const fields = {
    name: details.name, categoryId: details.categoryId, categoryName: category.name || '', price: details.price, unit: details.unit,
    ...location, ...capturedFields(request.data),
    startMode: details.startMode, requestedStartAt: Timestamp.fromMillis(details.requestedStartMs),
    durationUnit: details.durationUnit, durationValue: details.durationValue, durationMs: details.durationMs,
  };
  if (itemId !== undefined) {
    const ref = db.collection('quickItems').doc(String(itemId));
    const existing = await ref.get();
    if (!existing.exists || existing.data().ownerUid !== uid) throw new HttpsError('not-found', 'Item not found.');
    const photo = typeof submissionId === 'string' && submissionId ? `quickItems/${uid}/${submissionId}` : existing.data().photoPath;
    await verifyUploadedPhoto(photo);
    await ref.update({...fields, ...resetFields(), photoPath: photo, imageUrl: FieldValue.delete()});
    return {status: 'pending', itemId: ref.id};
  }
  if (typeof submissionId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(submissionId)) throw new HttpsError('invalid-argument', 'Take or choose the item photo first.');
  const photoPath = `quickItems/${uid}/${submissionId}`;
  await verifyUploadedPhoto(photoPath);
  const ids = await createItems(uid, account, [{...fields, photoPath}], now);
  return {status: 'pending', itemId: ids[0].id, remainingToday: ids[0].remaining};
});

/// Creates new pending items in one transaction, counting them all against today's limit.
async function createItems(uid, account, items, now) {
  const business = (await db.collection('settings').doc('business').get()).data() || {};
  const limit = dailyLimit(account.role, business), today = dayKey(now);
  const refs = items.map(() => db.collection('quickItems').doc());
  let used = 0;
  await db.runTransaction(async tx => {
    used = (await tx.get(db.collection('quickItems').where('ownerUid', '==', uid).where('dayKey', '==', today))).size;
    if (used + items.length > limit) throw new HttpsError('resource-exhausted', `Daily limit reached: you can add ${limit} items per day.`);
    items.forEach((fields, i) => tx.set(refs[i], {...ownerFields(uid, account), ...fields, imageUrl: '', status: 'pending', dayKey: today, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}));
  });
  return refs.map(ref => ({id: ref.id, remaining: limit - used - items.length}));
}

/// Up to 5 items with photos at once, all in one category with the same start and duration. A
/// vendor's GPS is checked once for the whole batch. Everything or nothing is saved.
exports.saveQuickItems = onCall(options, async request => {
  const uid = requireUser(request);
  const account = await activeAccount(uid);
  const now = Date.now();
  const list = request.data?.items;
  if (!Array.isArray(list) || list.length < 1 || list.length > MAX_BATCH) throw new HttpsError('invalid-argument', `Add 1 to ${MAX_BATCH} items at a time.`);
  const category = await categoryFor(String(request.data.categoryId || ''));
  requireAtShop(account, request.data);
  const location = await resolveLocation(account, request.data);
  const prepared = [];
  for (const [index, entry] of list.entries()) {
    const item = entry && typeof entry === 'object' ? entry : {};
    let details;
    try { details = parseDetails({...request.data, name: item.name, price: item.price, unit: item.unit}, now); }
    catch (error) { throw new HttpsError('invalid-argument', `Item ${index + 1}: ${error.message}`); }
    if (typeof item.submissionId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(item.submissionId)) throw new HttpsError('invalid-argument', `Item ${index + 1}: take or choose its photo first.`);
    const photoPath = `quickItems/${uid}/${item.submissionId}`;
    try { await verifyUploadedPhoto(photoPath); }
    catch (error) { throw new HttpsError(error.code || 'failed-precondition', `Item ${index + 1}: ${error.message}`); }
    prepared.push({
      name: details.name, categoryId: details.categoryId, categoryName: category.name || '', price: details.price, unit: details.unit,
      ...location, ...capturedFields(request.data), photoPath,
      startMode: details.startMode, requestedStartAt: Timestamp.fromMillis(details.requestedStartMs),
      durationUnit: details.durationUnit, durationValue: details.durationValue, durationMs: details.durationMs,
    });
  }
  if (new Set(prepared.map(p => p.photoPath)).size !== prepared.length) throw new HttpsError('invalid-argument', 'Each item needs its own photo.');
  const created = await createItems(uid, account, prepared, now);
  return {status: 'pending', itemIds: created.map(c => c.id), remainingToday: created.at(-1).remaining};
});

/// Show an expired / cancelled / rejected item again: new start and duration, back to the admin.
exports.reactivateQuickItem = onCall(options, async request => {
  const uid = requireUser(request);
  const account = await activeAccount(uid);
  const now = Date.now();
  const ref = db.collection('quickItems').doc(String(request.data?.itemId || ''));
  const existing = await ref.get();
  if (!existing.exists || existing.data().ownerUid !== uid) throw new HttpsError('not-found', 'Item not found.');
  requireAtShop(account, request.data);
  const old = existing.data();
  const details = parseDetails({...request.data, name: old.name, categoryId: old.categoryId, price: old.price, unit: old.unit}, now);
  await ref.update({
    startMode: details.startMode, requestedStartAt: Timestamp.fromMillis(details.requestedStartMs),
    durationUnit: details.durationUnit, durationValue: details.durationValue, durationMs: details.durationMs,
    ...resetFields(),
  });
  return {status: 'pending'};
});

exports.cancelQuickItem = onCall(options, async request => {
  const uid = requireUser(request);
  const ref = db.collection('quickItems').doc(String(request.data?.itemId || ''));
  const existing = await ref.get();
  if (!existing.exists || existing.data().ownerUid !== uid) throw new HttpsError('not-found', 'Item not found.');
  if (['cancelled', 'rejected'].includes(existing.data().status)) return {status: existing.data().status};
  await ref.update({status: 'cancelled', updatedAt: FieldValue.serverTimestamp()});
  return {status: 'cancelled'};
});

// ---- admin review ----------------------------------------------------------------------------
/// Approve or reject items one by one or all together. Approving starts the clock at the later of
/// now and the requested start. Rejecting a pending OR an already-approved item takes it off the site.
exports.reviewQuickItems = onCall({...options, timeoutSeconds: 120}, async request => {
  await requireAdmin(request);
  const {itemIds, approved, reason = ''} = request.data || {};
  if (!Array.isArray(itemIds) || !itemIds.length || itemIds.length > 100 || itemIds.some(id => typeof id !== 'string') || typeof approved !== 'boolean') throw new HttpsError('invalid-argument', 'Choose 1 to 100 items and a decision.');
  const bucket = getStorage().bucket();
  const result = {approved: 0, rejected: 0, skipped: 0};
  for (const id of itemIds) {
    const ref = db.collection('quickItems').doc(id);
    const snapshot = await ref.get();
    const item = snapshot.data();
    if (!item || !(item.status === 'pending' || (!approved && item.status === 'approved'))) { result.skipped++; continue; }
    if (!approved) {
      await ref.update({status: 'rejected', decisionReason: clean(reason, 500), decidedAt: FieldValue.serverTimestamp(), decidedBy: request.auth.uid, updatedAt: FieldValue.serverTimestamp()});
      result.rejected++;
      continue;
    }
    const now = Date.now();
    const window = approvedWindow(now, item.requestedStartAt.toMillis(), item.durationMs);
    const publicPath = `catalog/quick_${id}.jpg`;
    await bucket.file(item.photoPath).copy(bucket.file(publicPath));
    const imageUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(publicPath)}?alt=media`;
    await ref.update({
      status: 'approved', imageUrl, startsAt: Timestamp.fromMillis(window.startsAtMs), expiresAt: Timestamp.fromMillis(window.expiresAtMs),
      approvedAt: Timestamp.fromMillis(now), decisionReason: clean(reason, 500), decidedAt: FieldValue.serverTimestamp(), decidedBy: request.auth.uid, updatedAt: FieldValue.serverTimestamp(),
    });
    result.approved++;
  }
  return result;
});

/// Marks approved items whose time is over as 'expired' (hidden, never deleted). The site also
/// checks the clock itself, so an item disappears on time even before this runs.
async function expireQuickItems(now = Date.now()) {
  const approved = await db.collection('quickItems').where('status', '==', 'approved').get();
  let expired = 0;
  for (const doc of approved.docs) {
    if (doc.data().expiresAt.toMillis() <= now) { await doc.ref.update({status: 'expired', updatedAt: FieldValue.serverTimestamp()}); expired++; }
  }
  return expired;
}
exports.expireQuickItems = onSchedule({schedule: 'every 15 minutes', region: 'asia-south1', maxInstances: 1}, async () => { await expireQuickItems(); });
exports._quick = {expireQuickItems};
