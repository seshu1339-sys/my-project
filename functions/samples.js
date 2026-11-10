'use strict';
const {isAdminToken} = require('./role-auth');
// Sample data, so the whole system can be tried with made-up records and then emptied again before real data is added by hand.
//
// What counts as sample data:
//   - every record with isSample: true (the sample script, scripts/seed-samples.cjs, marks everything it makes), and
//   - everything that belongs to a SAMPLE ACCOUNT: an account listed in _sampleAccounts/<uid> (the script lists every account it
//     makes). Records a sample vendor, staff member or service provider then makes through the apps (their application, shop,
//     items, ads, photos, notices...) are found by their owner, even though the apps do not mark them.
// Never touched: any record that is not marked and has no sample owner; an administrator's account; a shared photo (the Product Image
// Library, the admin's own uploads) - only photos whose file name is made for a sample record or sample account are deleted.
//
//   sampleSummary     admin -> how many sample records there are, by collection (for the confirmation)
//   deleteAllSamples  admin -> deletes all of them, their photos and the sample accounts; returns what was deleted and logs it in
//                     _sampleDeletions
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {getAuth} = require('firebase-admin/auth');
const {requireAdminSession} = require('./admin-session');

// Collections where the sample script puts records (isSample: true).
const FLAGGED = [
  'users', 'vendorApplications', 'vendors', 'shops', 'products', 'services', 'categories', 'promotions', 'ads', 'adsPrivate',
  'adSubmissions', 'rightBoxAds', 'fieldStaff', 'providerApplications', 'providers', 'staffAdditions', 'productImageLibrary',
  'vendorShopPhotos', 'locations', 'quickItems', 'quickAccounts', 'vendorOffers', 'vendorTodaysOffers', 'vendorChanges',
  'vendorNotices', 'orders', 'complaints', 'reviews', 'notificationSubscribers', 'consents', 'accountStates', 'vendorPremium',
  'vendorPlanStatus', 'vendorPlanPeriods', 'paymentRequests', 'flashTickets',
];
// Records whose id IS the owner's uid.
const OWNER_DOCS = [
  'users', 'vendorApplications', 'vendors', 'shops', 'fieldStaff', 'providerApplications', 'providers', 'quickAccounts',
  'vendorPremium', 'vendorPlanStatus', 'consents', 'accountStates', 'notificationSubscribers',
];
// Records that name their owner in a field.
const OWNER_FIELDS = [
  ['products', 'ownerId'], ['services', 'ownerId'], ['services', 'providerId'], ['shops', 'ownerId'], ['ads', 'vendorId'],
  ['adSubmissions', 'vendorId'], ['rightBoxAds', 'vendorId'], ['vendorNotices', 'vendorId'], ['vendorChanges', 'vendorId'],
  ['vendorShopPhotos', 'vendorId'], ['staffAdditions', 'staffUid'], ['quickItems', 'ownerUid'], ['vendorOffers', 'vendorId'],
  ['vendorTodaysOffers', 'vendorId'], ['vendorPlanPeriods', 'vendorId'], ['paymentRequests', 'vendorId'], ['orders', 'userId'],
  ['complaints', 'userId'], ['adStats', 'vendorId'], ['adStatsDaily', 'vendorId'], ['adViews', 'vendorId'], ['usageOwnerDaily', 'ownerId'],
  // What a sample staff member added and the admin (or auto-approve) put live: the vendor, its shop and items, the provider and listing.
  ['vendors', 'addedByStaffUid'], ['shops', 'addedByStaffUid'], ['products', 'addedByStaffUid'], ['services', 'addedByStaffUid'], ['providers', 'addedByStaffUid'],
];
// Records of a sample shop (a staff-added vendor's items name the shop, not an owner).
const SHOP_FIELDS = [['products', 'shopId'], ['services', 'shopId'], ['vendorOffers', 'shopId']];
// Storage folders that hold an account's own (private) uploads: <folder>/<uid>/...
const PRIVATE_FOLDERS = [
  'vendorApplications', 'providerApplications', 'vendorProducts', 'vendorOffers', 'vendorTodaysOffers', 'vendorShopPhotos',
  'fieldStaffApplications', 'fieldSubmissions', 'staffAdditions', 'quickItems',
];
// Records that may have records under them (deleted with everything under them).
const NESTED = new Set(['products', 'orders', 'complaints', 'flashTickets']);
const SAMPLE_PHOTO_PREFIX = 'catalog/sample-';

const chunks = (list, size = 30) => {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
};

/// The sample accounts: listed in _sampleAccounts (by the script) and the owners named on sample-marked people records. Never an admin.
async function sampleOwners(db, auth) {
  const uids = new Set((await db.collection('_sampleAccounts').get()).docs.map(d => d.id));
  for (const name of ['users', 'vendorApplications', 'vendors', 'fieldStaff', 'providerApplications', 'providers']) {
    for (const doc of (await db.collection(name).where('isSample', '==', true).get()).docs) uids.add(doc.id);
  }
  if (auth) {
    for (const group of chunks([...uids], 100)) {
      const {users} = await auth.getUsers(group.map(uid => ({uid})));
      for (const user of users) if (user.customClaims?.admin === true) uids.delete(user.uid);
    }
  }
  return uids;
}

/// Every sample record (path -> DocumentReference), the sample accounts and the ids that name their photos.
async function findSamples(db, auth) {
  const owners = await sampleOwners(db, auth);
  const found = new Map();
  const add = doc => found.set(doc.ref.path, doc);
  for (const name of FLAGGED) {
    for (const doc of (await db.collection(name).where('isSample', '==', true).get()).docs) add(doc);
  }
  // A sample staff member's additions: the vendor / provider they put live is owned by the addition (its id), not by an account.
  const additionIds = [];
  for (const group of chunks([...owners])) {
    for (const doc of (await db.collection('staffAdditions').where('staffUid', 'in', group).get()).docs) { add(doc); additionIds.push(doc.id); }
  }
  for (const doc of found.values()) if (doc.ref.parent.id === 'staffAdditions' && !additionIds.includes(doc.id)) additionIds.push(doc.id);
  // Owners for the lookups below: the sample accounts and those additions (an addition is never an account, so it is not deleted in Auth).
  const uidList = [...owners, ...additionIds];
  for (const name of OWNER_DOCS) {
    for (const group of chunks(uidList, 100)) {
      const snaps = await db.getAll(...group.map(uid => db.collection(name).doc(uid)));
      for (const s of snaps) if (s.exists) add(s);
    }
  }
  for (const [name, field] of OWNER_FIELDS) {
    for (const group of chunks(uidList)) {
      for (const doc of (await db.collection(name).where(field, 'in', group).get()).docs) add(doc);
    }
  }
  // The shops found so far (a sample vendor's, or a staff-added sample shop), then everything that names one of them.
  const shopIds = [...found.values()].filter(d => d.ref.parent.id === 'shops').map(d => d.id);
  for (const [name, field] of SHOP_FIELDS) {
    for (const group of chunks(shopIds)) {
      for (const doc of (await db.collection(name).where(field, 'in', group).get()).docs) add(doc);
    }
  }
  // The counts, the admin-only side and the view log of every sample ad.
  const adIds = [...found.values()].filter(d => ['ads', 'rightBoxAds'].includes(d.ref.parent.id)).map(d => d.id);
  for (const group of chunks(adIds, 100)) {
    for (const name of ['adStats', 'adsPrivate']) {
      const snaps = await db.getAll(...group.map(id => db.collection(name).doc(id)));
      for (const s of snaps) if (s.exists) add(s);
    }
  }
  for (const group of chunks(adIds)) {
    for (const name of ['adStatsDaily', 'adViews']) {
      for (const doc of (await db.collection(name).where('adId', 'in', group).get()).docs) add(doc);
    }
  }
  // The IDs (VEN-/STF-/SRV-...) reserved for sample accounts.
  for (const group of chunks(uidList)) {
    for (const doc of (await db.collection('_vendorCodes').where('owner', 'in', group).get()).docs) add(doc);
  }
  for (const uid of uidList) {
    const ref = db.collection('_sampleAccounts').doc(uid);
    const snap = await ref.get();
    if (snap.exists) add(snap);
  }
  const tokens = new Set([...owners, ...[...found.values()].map(d => d.id)]);
  return {found, owners, adIds: new Set(adIds), tokens};
}

/// The Storage path of a photo link into this project's bucket (or the emulator's), else null.
function storagePath(url, bucketName) {
  if (typeof url !== 'string' || !url.includes('/o/')) return null;
  const m = url.match(/\/v0\/b\/([^/]+)\/o\/([^?#]+)/);
  if (!m || (bucketName && m[1] !== bucketName)) return null;
  try { return decodeURIComponent(m[2]); } catch (_) { return null; }
}

/// Every photo link in a record (any field, nested lists and maps too).
function photoLinks(value, out = []) {
  if (typeof value === 'string') { if (value.includes('/v0/b/')) out.push(value); }
  else if (Array.isArray(value)) value.forEach(v => photoLinks(v, out));
  else if (value && typeof value === 'object' && !(typeof value.toMillis === 'function')) Object.values(value).forEach(v => photoLinks(v, out));
  return out;
}

/// A public photo made for a sample record: catalog/sample-..., or a catalog copy whose name carries a sample id (shop_<uid>_1.jpg,
/// staffvendor_<id>_2.jpg, <productId>_1.jpg, provider_<uid>.jpg, quick_<id>.jpg). A shared photo (the library's, the admin's) never is.
function isSamplePhoto(path, tokens) {
  if (!path.startsWith('catalog/')) return false;
  if (path.startsWith(SAMPLE_PHOTO_PREFIX)) return true;
  const parts = path.slice('catalog/'.length).split(/[_.]/);
  return parts.some(p => tokens.has(p));
}

/// How many sample records there are, by collection.
async function summary(db, auth) {
  const {found, owners} = await findSamples(db, auth);
  const byCollection = {};
  for (const doc of found.values()) byCollection[doc.ref.parent.id] = (byCollection[doc.ref.parent.id] || 0) + 1;
  const boxes = sampleBoxes((await db.collection('settings').doc('rightAdBoxes').get()).data() || {});
  return {total: found.size, byCollection, accounts: owners.size, rightBoxes: boxes.length};
}

/// The Right Side Ad Boxes that hold a sample photo.
function sampleBoxes(settings) {
  const out = [];
  for (let n = 1; n <= 60; n++) {
    const image = String(settings[`box${n}Image`] || '');
    if (settings[`box${n}Sample`] === true || image.includes(encodeURIComponent(SAMPLE_PHOTO_PREFIX)) || image.includes(SAMPLE_PHOTO_PREFIX)) out.push(n);
  }
  return out;
}

/// Deletes every sample record, their photos, the sample accounts, and the sample photos in the Right Side Ad Boxes.
async function deleteSamples(db, bucket, auth, {by = ''} = {}) {
  const {found, owners, adIds, tokens} = await findSamples(db, auth);
  const result = {records: 0, byCollection: {}, photos: 0, accounts: 0, rightBoxes: 0};
  // Photos first (their links are in the records about to go).
  const paths = new Set();
  for (const doc of found.values()) {
    for (const url of photoLinks(doc.data())) {
      const path = storagePath(url, bucket?.name);
      if (path && (isSamplePhoto(path, tokens) || PRIVATE_FOLDERS.some(f => [...owners].some(uid => path.startsWith(`${f}/${uid}/`))))) paths.add(path);
    }
  }
  if (bucket) {
    const [samplePhotos] = await bucket.getFiles({prefix: SAMPLE_PHOTO_PREFIX});
    samplePhotos.forEach(f => paths.add(f.name));
    for (const uid of owners) {
      for (const folder of PRIVATE_FOLDERS) {
        const [files] = await bucket.getFiles({prefix: `${folder}/${uid}/`});
        files.forEach(f => paths.add(f.name));
      }
    }
    for (const path of paths) {
      try { await bucket.file(path).delete({ignoreNotFound: true}); result.photos++; } catch (error) { console.warn('Sample photo not deleted', path, error.message); }
    }
  }
  // The boxes with a sample photo, and the box links to sample shop ads.
  const boxesRef = db.collection('settings').doc('rightAdBoxes');
  const boxes = (await boxesRef.get()).data() || {};
  const clear = {};
  for (const n of sampleBoxes(boxes)) {
    for (const k of ['Image', 'Target', 'Color', 'StartsAt', 'EndsAt', 'Sample', 'AdId']) clear[`box${n}${k}`] = FieldValue.delete();
    result.rightBoxes++;
  }
  for (let n = 1; n <= 60; n++) if (adIds.has(String(boxes[`box${n}AdId`] || ''))) clear[`box${n}AdId`] = FieldValue.delete();
  if (Object.keys(clear).length) await boxesRef.set(clear, {merge: true});
  // Sample city codes (settings/cityCodes rows marked sample).
  const cityRef = db.collection('settings').doc('cityCodes');
  const city = (await cityRef.get()).data();
  if (Array.isArray(city?.rows) && city.rows.some(r => r?.sample === true)) await cityRef.set({rows: city.rows.filter(r => r?.sample !== true)}, {merge: true});
  // The records.
  let batch = db.batch(), pending = 0;
  for (const doc of found.values()) {
    const name = doc.ref.parent.id;
    if (NESTED.has(name)) await db.recursiveDelete(doc.ref);
    else {
      batch.delete(doc.ref);
      if (++pending === 400) { await batch.commit(); batch = db.batch(); pending = 0; }
    }
    result.records++;
    result.byCollection[name] = (result.byCollection[name] || 0) + 1;
  }
  if (pending) await batch.commit();
  // The accounts.
  if (auth && owners.size) {
    for (const group of chunks([...owners], 1000)) {
      const out = await auth.deleteUsers(group);
      result.accounts += out.successCount;
    }
  }
  await db.collection('_sampleDeletions').add({...result, by, at: FieldValue.serverTimestamp()});
  return result;
}

const options = {region: 'us-central1', maxInstances: 2, invoker: 'public', timeoutSeconds: 540, memory: '512MiB'};
async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
}

exports.sampleSummary = onCall(options, async request => {
  await requireAdmin(request);
  return summary(getFirestore(), getAuth());
});

exports.deleteAllSamples = onCall(options, async request => {
  await requireAdmin(request);
  if (request.data?.confirm !== 'DELETE') throw new HttpsError('invalid-argument', 'Type DELETE to confirm.');
  return deleteSamples(getFirestore(), getStorage().bucket(), getAuth(), {by: request.auth.uid});
});

exports._samples = {findSamples, summary, deleteSamples, isSamplePhoto, storagePath, photoLinks, sampleBoxes, sampleOwners, FLAGGED, OWNER_DOCS, OWNER_FIELDS, PRIVATE_FOLDERS, SAMPLE_PHOTO_PREFIX};
