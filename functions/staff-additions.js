'use strict';
// Staff "Add": approved field staff add vendors and service providers for people who have no account of their own.
// The staff member is at the place: their GPS is the vendor's (or provider's) location (nothing is added without it). Everything waits
// for the admin as staffAdditions/<id>:
//   kind          'vendor' or 'provider'
//   status        pending | approved | rejected
//   staffUid, staffCode, staffName   who added it (the admin report counts these)
//   vendor        name, phone, ownerName, shopCategory, address, pincode, description, gpsAddress
//   latitude, longitude (+ town, district, state from the pincode)
//   photoPaths    the vendor's 3 photos (private: staffAdditions/<staffUid>/<id>/vendor_1..3)
//   items         1 to 2 items from the admin's library (libraryItemId, name, unitType, quantity, unit, price) with 2-3 photos each
//   vendorCode    the Vendor ID it gets (VEN-NRPM-116-001), reserved when it is added
// A provider addition has instead: provider (name, phone, address, pincode, gpsAddress), serviceTypeId / serviceName / serviceTypeKey
// (the admin's service type), hourlyRate, photoPaths (2-3 photos of their work: work_1..3) and providerCode (SRV-NRPM-116-001).
// Approved, a provider is listed in services (prov-<id>, like a provider who registered themselves: the town and an approximate
// location only) with the work photos, and gets a providers/<id> record.
// Approved: the vendor record, its shop (with the photos, the address and the phone) and its items go live (vendors/<id>,
// shops/<id>, products) with public copies of the photos; the private originals are removed. The items follow the vendor rules:
// at most the vendor's item limit (2 unless the admin allows more), and each price lasts 24 hours (vendor-prices.js), after which the
// staff member who added the vendor enters a new one (renewStaffVendorPrice).
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {requireAdminSession} = require('./admin-session');
const {locationStamp} = require('./places');
const {validCoordinate, vendorItemUnit, DEFAULT_VENDOR_ITEM_LIMIT} = require('./domain');
const {accountCodeFor} = require('./vendor-id');
const {freshPriceFields} = require('./vendor-prices');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};

const VENDOR_PHOTOS = 3;
const MIN_ITEM_PHOTOS = 2, MAX_ITEM_PHOTOS = 3;
// Photos of a service provider's work.
const MIN_WORK_PHOTOS = 2, MAX_WORK_PHOTOS = 3;
// A new item starts with this many in stock, like a vendor's own (index.js DEFAULT_VENDOR_ITEM_STOCK).
const ITEM_STOCK = 99;

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
async function requireActiveStaff(uid) {
  const staff = (await db.collection('fieldStaff').doc(uid).get()).data();
  if (!staff || staff.status !== 'active') throw new HttpsError('permission-denied', 'Your field staff access must be approved before you can add anything.');
  return staff;
}

const words = (value, min, max, label) => {
  const v = typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
  if (v.length < min || v.length > max) throw Error(min ? `Provide ${label} (${min}-${max} characters).` : `${label} can be at most ${max} characters.`);
  return v;
};
const money = value => {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > 10000000) throw Error('Enter a price above 0.');
  return Math.round(value * 100) / 100;
};

/// The checked details of a vendor a staff member adds. Throws Error(message).
function staffVendorDetails(data = {}) {
  const vendor = data.vendor || {};
  const phone = typeof vendor.phone === 'string' ? vendor.phone.trim() : '';
  if (!/^\+?[0-9][0-9 -]{6,17}$/.test(phone)) throw Error("Provide the vendor's phone number.");
  const pincode = typeof vendor.pincode === 'string' ? vendor.pincode.trim() : '';
  if (!/^\d{6}$/.test(pincode)) throw Error('Provide a valid six-digit pincode.');
  // The staff member's own GPS, where they are: the vendor's location.
  if (!validCoordinate(data.latitude) || !validCoordinate(data.longitude)) throw Error('Turn on your location and capture it: the vendor is added at your location.');
  const items = Array.isArray(data.items) ? data.items : [];
  if (items.length < 1) throw Error('Add at least one item the vendor sells.');
  if (items.length > DEFAULT_VENDOR_ITEM_LIMIT) throw Error(`A vendor can have ${DEFAULT_VENDOR_ITEM_LIMIT} items. The admin can allow more later.`);
  return {
    vendor: {
      name: words(vendor.name, 2, 120, "the vendor's name"), phone,
      ownerName: words(vendor.ownerName, 0, 100, "The owner's name"), shopCategory: words(vendor.shopCategory, 0, 80, 'The shop category'),
      address: words(vendor.address, 5, 500, 'the address'), pincode, description: words(vendor.description, 0, 1000, 'The description'),
      ...(typeof data.gpsAddress === 'string' && data.gpsAddress.trim() ? {gpsAddress: data.gpsAddress.trim().replace(/\s+/g, ' ').slice(0, 500)} : {}),
    },
    latitude: data.latitude, longitude: data.longitude,
    items: items.map((item, i) => {
      if (typeof item?.libraryItemId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(item.libraryItemId)) throw Error(`Item ${i + 1}: choose an item from the list.`);
      if (!['kg', 'pcs'].includes(item.unitType)) throw Error(`Item ${i + 1}: choose Kg or Pieces.`);
      if (!Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 10) throw Error(`Item ${i + 1}: choose a quantity from 1 to 10.`);
      if (!Number.isInteger(item.photoCount) || item.photoCount < MIN_ITEM_PHOTOS || item.photoCount > MAX_ITEM_PHOTOS) throw Error(`Item ${i + 1}: add ${MIN_ITEM_PHOTOS} or ${MAX_ITEM_PHOTOS} photos.`);
      let price;
      try { price = money(item.price); } catch (error) { throw Error(`Item ${i + 1}: ${error.message}`); }
      return {libraryItemId: item.libraryItemId, unitType: item.unitType, quantity: item.quantity, price, photoCount: item.photoCount};
    }),
  };
}

/// The checked details of a service provider a staff member adds. Throws Error(message).
function staffProviderDetails(data = {}) {
  const provider = data.provider || {};
  const phone = typeof provider.phone === 'string' ? provider.phone.trim() : '';
  if (!/^\+?[0-9][0-9 -]{6,17}$/.test(phone)) throw Error("Provide the provider's phone number.");
  const pincode = typeof provider.pincode === 'string' ? provider.pincode.trim() : '';
  if (!/^\d{6}$/.test(pincode)) throw Error('Provide a valid six-digit pincode.');
  if (!validCoordinate(data.latitude) || !validCoordinate(data.longitude)) throw Error('Turn on your location and capture it: the provider is added at your location.');
  if (typeof data.serviceTypeId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(data.serviceTypeId)) throw Error('Choose the service from the list.');
  const rate = data.hourlyRate;
  if (typeof rate !== 'number' || !Number.isFinite(rate) || rate <= 0 || rate > 100000) throw Error('Enter the charge per hour (more than 0).');
  if (!Number.isInteger(data.photoCount) || data.photoCount < MIN_WORK_PHOTOS || data.photoCount > MAX_WORK_PHOTOS) throw Error(`Add ${MIN_WORK_PHOTOS} or ${MAX_WORK_PHOTOS} photos of their work.`);
  return {
    provider: {
      name: words(provider.name, 2, 100, "the provider's name"), phone, address: words(provider.address, 0, 500, 'The address'), pincode,
      ...(typeof data.gpsAddress === 'string' && data.gpsAddress.trim() ? {gpsAddress: data.gpsAddress.trim().replace(/\s+/g, ' ').slice(0, 500)} : {}),
    },
    latitude: data.latitude, longitude: data.longitude, serviceTypeId: data.serviceTypeId, hourlyRate: Math.round(rate * 100) / 100, photoCount: data.photoCount,
  };
}

const photoFolder = (staffUid, additionId) => `staffAdditions/${staffUid}/${additionId}`;

async function verifyPhoto(path, label) {
  const file = getStorage().bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) throw new HttpsError('failed-precondition', `Add ${label}.`);
  const [metadata] = await file.getMetadata();
  if (!/^image\/(jpeg|png|webp)$/.test(metadata.contentType || '') || !(Number(metadata.size) > 0)) throw new HttpsError('failed-precondition', `${label[0].toUpperCase()}${label.slice(1)} is not a valid photo.`);
}

exports.submitStaffVendor = onCall({...options, timeoutSeconds: 120}, async request => {
  const uid = requireUser(request);
  const staff = await requireActiveStaff(uid);
  const additionId = request.data?.additionId;
  if (typeof additionId !== 'string' || !/^[A-Za-z0-9_-]{8,64}$/.test(additionId)) throw new HttpsError('invalid-argument', 'Invalid addition id.');
  const ref = db.collection('staffAdditions').doc(additionId);
  const existing = (await ref.get()).data();
  if (existing) {
    if (existing.staffUid !== uid) throw new HttpsError('already-exists', 'Invalid addition id.');
    return {status: existing.status, additionId, vendorCode: existing.vendorCode};
  }
  let details;
  try { details = staffVendorDetails(request.data || {}); } catch (error) { throw new HttpsError('invalid-argument', error.message); }
  // The items come from the admin's library: their names and categories are taken from there.
  const library = await Promise.all(details.items.map(item => db.collection('productImageLibrary').doc(item.libraryItemId).get()));
  library.forEach((doc, i) => {
    if (!doc.exists || doc.data().active === false) throw new HttpsError('failed-precondition', `Item ${i + 1}: choose an item from the list.`);
  });
  const folder = photoFolder(uid, additionId);
  const photoPaths = [];
  for (let n = 1; n <= VENDOR_PHOTOS; n++) {
    await verifyPhoto(`${folder}/vendor_${n}`, n === 1 ? "the vendor's photo" : `extra photo ${n - 1}`);
    photoPaths.push(`${folder}/vendor_${n}`);
  }
  const items = [];
  for (const [i, item] of details.items.entries()) {
    const paths = [];
    for (let n = 1; n <= item.photoCount; n++) {
      await verifyPhoto(`${folder}/item${i + 1}_${n}`, `photo ${n} of item ${i + 1}`);
      paths.push(`${folder}/item${i + 1}_${n}`);
    }
    const lib = library[i].data();
    const {photoCount: _count, ...rest} = item;
    items.push({...rest, name: String(lib.name || '').trim() || 'Item', categoryId: lib.categoryId || '', libraryImageUrl: lib.imageUrl || '', unit: vendorItemUnit(item.unitType, item.quantity), photoPaths: paths});
  }
  const vendorCode = await accountCodeFor(db, 'VEN', {pincode: details.vendor.pincode, existing: '', owner: additionId});
  await ref.set({
    kind: 'vendor', status: 'pending', staffUid: uid, staffCode: staff.staffCode || '', staffName: staff.name || '',
    vendor: details.vendor, ...locationStamp({pincode: details.vendor.pincode, latitude: details.latitude, longitude: details.longitude}),
    photoPaths, items, vendorCode, submittedAt: FieldValue.serverTimestamp(),
  });
  return {status: 'pending', additionId, vendorCode};
});

exports.submitStaffProvider = onCall({...options, timeoutSeconds: 120}, async request => {
  const uid = requireUser(request);
  const staff = await requireActiveStaff(uid);
  const additionId = request.data?.additionId;
  if (typeof additionId !== 'string' || !/^[A-Za-z0-9_-]{8,64}$/.test(additionId)) throw new HttpsError('invalid-argument', 'Invalid addition id.');
  const ref = db.collection('staffAdditions').doc(additionId);
  const existing = (await ref.get()).data();
  if (existing) {
    if (existing.staffUid !== uid) throw new HttpsError('already-exists', 'Invalid addition id.');
    return {status: existing.status, additionId, providerCode: existing.providerCode};
  }
  let details;
  try { details = staffProviderDetails(request.data || {}); } catch (error) { throw new HttpsError('invalid-argument', error.message); }
  const type = (await db.collection('services').doc(details.serviceTypeId).get()).data();
  if (!type || type.kind !== 'serviceType' || type.active === false) throw new HttpsError('invalid-argument', 'Choose the service from the list.');
  const folder = photoFolder(uid, additionId);
  const photoPaths = [];
  for (let n = 1; n <= details.photoCount; n++) {
    await verifyPhoto(`${folder}/work_${n}`, `photo ${n} of their work`);
    photoPaths.push(`${folder}/work_${n}`);
  }
  const providerCode = await accountCodeFor(db, 'SRV', {pincode: details.provider.pincode, existing: '', owner: additionId});
  await ref.set({
    kind: 'provider', status: 'pending', staffUid: uid, staffCode: staff.staffCode || '', staffName: staff.name || '',
    provider: details.provider, serviceTypeId: details.serviceTypeId, serviceName: String(type.name || ''),
    serviceTypeKey: String(type.typeId || details.serviceTypeId.replace(/^type-/, '')), hourlyRate: details.hourlyRate,
    ...locationStamp({pincode: details.provider.pincode, latitude: details.latitude, longitude: details.longitude}),
    photoPaths, providerCode, submittedAt: FieldValue.serverTimestamp(),
  });
  return {status: 'pending', additionId, providerCode};
});

const publicUrl = (bucket, path) => `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media`;

/// Puts an approved vendor addition live: public copies of the photos, the vendor record, the shop and the items. Returns the ids.
async function publishStaffVendor(ref, addition, decidedBy) {
  const id = ref.id;
  const bucket = getStorage().bucket();
  const copy = async (from, to) => {
    await bucket.file(from).copy(bucket.file(to));
    return publicUrl(bucket, to);
  };
  const shopPhotos = [];
  for (const [i, path] of addition.photoPaths.entries()) shopPhotos.push(await copy(path, `catalog/staffvendor_${id}_${i + 1}.jpg`));
  const place = locationStamp({pincode: addition.vendor.pincode, latitude: addition.latitude, longitude: addition.longitude});
  const digits = String(addition.vendor.phone || '').replace(/[^0-9]/g, '');
  const added = {addedByStaffUid: addition.staffUid, addedByStaffCode: addition.staffCode || '', additionId: id};
  const batch = db.batch();
  batch.set(db.collection('vendors').doc(id), {
    vendorId: id, name: addition.vendor.name, ownerName: addition.vendor.ownerName || '', phone: addition.vendor.phone, shopId: id,
    status: 'approved', verified: false, vendorCode: addition.vendorCode, ...place, noLogin: true, ...added,
    approvedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.set(db.collection('shops').doc(id), {
    name: addition.vendor.name, ownerId: id, phone: addition.vendor.phone, whatsapp: digits.length === 10 ? `91${digits}` : digits,
    address: addition.vendor.address, category: addition.vendor.shopCategory || '', description: addition.vendor.description || '',
    imageUrl: shopPhotos[0] || '', images: shopPhotos.slice(1), ...place, active: true, vendorCode: addition.vendorCode, ...added,
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  const productIds = [];
  for (const item of addition.items) {
    const productRef = db.collection('products').doc();
    const photos = [];
    for (const [j, path] of item.photoPaths.entries()) photos.push(await copy(path, `catalog/${productRef.id}_${j + 1}.jpg`));
    batch.set(productRef, {
      name: item.name, imageUrl: photos[0] || item.libraryImageUrl || '', images: photos.slice(1), libraryImageUrl: item.libraryImageUrl || '',
      categoryId: item.categoryId || '', libraryItemId: item.libraryItemId, unitType: item.unitType, quantity: item.quantity, unit: item.unit,
      price: item.price, ...freshPriceFields(), kind: 'product', stock: ITEM_STOCK, ownerId: id, shopId: id, ...place, active: true, ...added,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    productIds.push(productRef.id);
  }
  batch.update(ref, {status: 'approved', vendorId: id, shopId: id, productIds, decidedAt: FieldValue.serverTimestamp(), decidedBy});
  await batch.commit();
  return {vendorId: id, productIds};
}

// Two decimals of a degree: about 1 km, like a provider who registered themselves (providers.js).
const approximate = value => Math.round(value * 100) / 100;

/// Puts an approved provider addition live: the listing in services (with public copies of the work photos) and the provider record.
async function publishStaffProvider(ref, addition, decidedBy) {
  const id = ref.id;
  const bucket = getStorage().bucket();
  const photos = [];
  for (const [i, path] of addition.photoPaths.entries()) {
    const to = `catalog/staffprovider_${id}_${i + 1}.jpg`;
    await bucket.file(path).copy(bucket.file(to));
    photos.push(publicUrl(bucket, to));
  }
  const listingId = `prov-${id}`;
  const digits = String(addition.provider.phone || '').replace(/[^0-9]/g, '');
  const added = {addedByStaffUid: addition.staffUid, addedByStaffCode: addition.staffCode || '', additionId: id};
  const batch = db.batch();
  batch.set(db.collection('services').doc(listingId), {
    kind: 'service', providerId: id, ownerId: id, name: addition.provider.name, typeId: addition.serviceTypeKey, serviceName: addition.serviceName,
    description: `${addition.serviceName} • ₹${addition.hourlyRate} per hour`, price: addition.hourlyRate, unit: 'per hour',
    // Booked by calling the provider; the town and an approximate location only, never the exact place.
    stock: 0, phone: addition.provider.phone, whatsapp: digits.length === 10 ? `91${digits}` : digits, imageUrl: photos[0] || '', images: photos.slice(1),
    ...locationStamp({pincode: addition.provider.pincode, latitude: approximate(addition.latitude), longitude: approximate(addition.longitude)}),
    providerCode: addition.providerCode, active: true, order: 1000, ...added, createdAt: FieldValue.serverTimestamp(),
  });
  batch.set(db.collection('providers').doc(id), {
    providerId: id, name: addition.provider.name, phone: addition.provider.phone, status: 'approved', listingId, serviceTypeId: addition.serviceTypeId,
    providerCode: addition.providerCode, noLogin: true, ...added, approvedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.update(ref, {status: 'approved', providerId: id, listingId, decidedAt: FieldValue.serverTimestamp(), decidedBy});
  await batch.commit();
  return {providerId: id, listingId};
}

/// Removes the private originals of an addition once it is decided (the live copies are in catalog/).
async function removePrivatePhotos(addition) {
  const bucket = getStorage().bucket();
  const paths = [...(addition.photoPaths || []), ...(addition.items || []).flatMap(item => item.photoPaths || [])];
  await Promise.all(paths.map(path => bucket.file(path).delete({ignoreNotFound: true})));
}

// Admin: approve (the vendor goes live) or reject (with a reason the staff member sees) a staff addition.
exports.reviewStaffAddition = onCall({...options, timeoutSeconds: 120}, async request => {
  await requireAdmin(request);
  const {additionId, approved, reason = ''} = request.data || {};
  if (typeof additionId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(additionId) || typeof approved !== 'boolean') throw new HttpsError('invalid-argument', 'Provide the addition and the decision.');
  const ref = db.collection('staffAdditions').doc(additionId);
  const addition = (await ref.get()).data();
  if (!addition) throw new HttpsError('not-found', 'Addition not found.');
  if (addition.status !== 'pending') throw new HttpsError('failed-precondition', 'This addition was already reviewed.');
  if (!approved) {
    const note = String(reason).trim().slice(0, 500);
    if (note.length < 3) throw new HttpsError('invalid-argument', 'Give the staff member the reason for rejecting.');
    await ref.update({status: 'rejected', decisionReason: note, decidedAt: FieldValue.serverTimestamp(), decidedBy: request.auth.uid});
    await removePrivatePhotos(addition);
    return {status: 'rejected'};
  }
  if (!['vendor', 'provider'].includes(addition.kind)) throw new HttpsError('failed-precondition', 'Unknown kind of addition.');
  const out = addition.kind === 'provider' ? await publishStaffProvider(ref, addition, request.auth.uid) : await publishStaffVendor(ref, addition, request.auth.uid);
  await removePrivatePhotos(addition);
  return {status: 'approved', ...out};
});

// The staff member who added a vendor enters a new price for one of its items (a price lasts 24 hours, like a vendor's own).
exports.renewStaffVendorPrice = onCall(options, async request => {
  const uid = requireUser(request);
  await requireActiveStaff(uid);
  const {productId} = request.data || {};
  if (typeof productId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(productId)) throw new HttpsError('invalid-argument', 'Choose the item.');
  let price;
  try { price = money(request.data?.price); } catch (error) { throw new HttpsError('invalid-argument', error.message); }
  const productRef = db.collection('products').doc(productId);
  const product = (await productRef.get()).data();
  if (!product || product.addedByStaffUid !== uid) throw new HttpsError('permission-denied', 'You can change the prices only of the vendors you added.');
  const vendor = (await db.collection('vendors').doc(product.ownerId).get()).data();
  if (!vendor || vendor.status !== 'approved') throw new HttpsError('failed-precondition', 'This vendor is not active.');
  await productRef.update({price, ...freshPriceFields(), updatedAt: FieldValue.serverTimestamp()});
  return {price};
});

exports._staffAdditions = {staffVendorDetails, staffProviderDetails, VENDOR_PHOTOS, MIN_ITEM_PHOTOS, MAX_ITEM_PHOTOS, MIN_WORK_PHOTOS, MAX_WORK_PHOTOS};
