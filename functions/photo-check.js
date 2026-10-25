'use strict';
// The "Google check" of a photo the admin is reviewing (vendor spec section 7: is the photo genuine?). For one private photo it finds:
//   online      whether Google has the same picture on the internet (Cloud Vision web detection): 'none' (not found),
//               'partial' (similar pictures), 'full' (the same picture is online: probably copied), or 'limit' / 'error' when the
//               check could not run (this month's free scans are used up, or the Cloud Vision API is not switched on)
//   duplicates  every earlier checked photo that is the same picture: exactly the same file, or the same picture saved again
//               (a "fingerprint" of the image: a 64-bit difference hash, nearly equal for a resized or recompressed copy)
// The result is kept in photoChecks/<path with ~ for />, which the admin reads; the staff-addition approval needs one for every photo.
// Google's free tier is 1000 web-detection scans a month: the scans are counted in photoCheckUsage/<YYYY-MM> and stop at the limit
// (settings/photoCheck.monthlyLimit, 1000 when not set), so the check never costs money. The admin sees this month's count.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {createHash} = require('node:crypto');
const {requireAdminSession} = require('./admin-session');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public', timeoutSeconds: 120};

const FREE_SCANS_PER_MONTH = 1000;
// Two fingerprints this close (bits out of 64) are the same picture.
const SAME_PICTURE_BITS = 6;

// The photos that can be checked: the ones the admin reviews.
const CHECKABLE = /^(staffAdditions\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+\/(vendor_[1-3]|item[1-9]_[1-3]|work_[1-3])|vendorShopPhotos\/[A-Za-z0-9_-]+\/shopPhoto[1-9]|providerApplications\/[A-Za-z0-9_-]+\/photo|vendorApplications\/[A-Za-z0-9_-]+\/(vendorPhoto|shopPhoto)|fieldSubmissions\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+)$/;

/// The photoChecks document id for a Storage path (a document id cannot contain "/").
const checkId = path => path.split('/').join('~');
/// The month a scan is counted in, in India (YYYY-MM).
const monthKey = (now = Date.now()) => new Date(now + 19800000).toISOString().slice(0, 7);

/// Whose photo a path is, in words, for the admin.
function describePath(path) {
  let m = path.match(/^staffAdditions\/[^/]+\/([^/]+)\/(vendor|item(\d)|work)_(\d)$/);
  if (m) return {kind: 'staffAddition', ownerId: m[1], label: m[2] === 'vendor' ? `vendor photo ${m[4]}` : m[2] === 'work' ? `work photo ${m[4]}` : `item ${m[3]} photo ${m[4]}`};
  m = path.match(/^vendorShopPhotos\/([^/]+)\/shopPhoto(\d)$/);
  if (m) return {kind: 'vendor', ownerId: m[1], label: `shop photo ${m[2]}`};
  m = path.match(/^providerApplications\/([^/]+)\/photo$/);
  if (m) return {kind: 'provider', ownerId: m[1], label: 'provider photo'};
  m = path.match(/^vendorApplications\/([^/]+)\/(vendorPhoto|shopPhoto)$/);
  if (m) return {kind: 'vendorApplication', ownerId: m[1], label: m[2] === 'vendorPhoto' ? 'vendor photo' : 'shop photo'};
  m = path.match(/^fieldSubmissions\/([^/]+)\/(.+)$/);
  if (m) return {kind: 'fieldSubmission', ownerId: m[1], label: 'field entry photo'};
  return {kind: 'other', ownerId: '', label: path};
}

/// The 64-bit difference hash of an image (16 hex characters), or '' when it cannot be read as an image.
async function fingerprint(bytes) {
  try {
    const sharp = require('sharp');
    const {data} = await sharp(bytes).grayscale().resize(9, 8, {fit: 'fill'}).raw().toBuffer({resolveWithObject: true});
    let bits = '';
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) bits += data[y * 9 + x] > data[y * 9 + x + 1] ? '1' : '0';
    return BigInt(`0b${bits}`).toString(16).padStart(16, '0');
  } catch (_) {
    return '';
  }
}

/// How many bits two fingerprints differ in.
function distance(a, b) {
  let x = BigInt(`0x${a}`) ^ BigInt(`0x${b}`), n = 0;
  while (x) { n += Number(x & 1n); x >>= 1n; }
  return n;
}

/// The 8 one-byte bands of a fingerprint: two pictures within SAME_PICTURE_BITS bits share at least one band, so a lookup by band
/// finds every candidate.
const bands = hash => Object.fromEntries(Array.from({length: 8}, (_, i) => [`b${i}`, hash.slice(i * 2, i * 2 + 2)]));

/// Cloud Vision web detection for an image. Replaced in tests (the emulator has no Google credentials).
let webDetection = async bytes => {
  const {GoogleAuth} = require('google-auth-library');
  const client = await new GoogleAuth({scopes: ['https://www.googleapis.com/auth/cloud-platform']}).getClient();
  const response = await client.request({
    url: 'https://vision.googleapis.com/v1/images:annotate',
    method: 'POST',
    data: {requests: [{image: {content: bytes.toString('base64')}, features: [{type: 'WEB_DETECTION', maxResults: 10}]}]},
  });
  const result = response.data?.responses?.[0] || {};
  if (result.error) throw Error(result.error.message || 'Cloud Vision could not check the photo.');
  return result.webDetection || {};
};

/// What Google's answer means for the admin.
function onlineVerdict(web = {}) {
  const full = web.fullMatchingImages || [], partial = web.partialMatchingImages || [], pages = web.pagesWithMatchingImages || [];
  return {
    online: full.length ? 'full' : partial.length || pages.length ? 'partial' : 'none',
    matches: [...full, ...partial].map(m => String(m.url || '')).filter(Boolean).slice(0, 5),
    pages: pages.map(p => ({url: String(p.url || ''), title: String(p.pageTitle || '').replace(/<[^>]+>/g, '').slice(0, 200)})).filter(p => p.url).slice(0, 5),
    bestGuess: String(web.bestGuessLabels?.[0]?.label || ''),
  };
}

/// Reserves one scan of this month's free allowance; false when it is used up.
async function reserveScan(now) {
  const limitSetting = Number((await db.collection('settings').doc('photoCheck').get()).data()?.monthlyLimit);
  const limit = Number.isInteger(limitSetting) && limitSetting >= 0 && limitSetting <= FREE_SCANS_PER_MONTH ? limitSetting : FREE_SCANS_PER_MONTH;
  const ref = db.collection('photoCheckUsage').doc(monthKey(now));
  return db.runTransaction(async tx => {
    const used = Number((await tx.get(ref)).data()?.scans) || 0;
    if (used >= limit) return false;
    tx.set(ref, {month: monthKey(now), scans: used + 1, limit, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return true;
  });
}
const releaseScan = now => db.collection('photoCheckUsage').doc(monthKey(now)).set({scans: FieldValue.increment(-1)}, {merge: true});

/// Checks one photo (see the top of this file) and keeps the result. [checkedBy] is the admin's uid.
async function checkPhotoAt(path, checkedBy, now = Date.now()) {
  const file = getStorage().bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) throw new HttpsError('not-found', 'This photo is not there any more.');
  const [bytes] = await file.download();
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  const hash = await fingerprint(bytes);
  const owner = describePath(path);

  // ---- the same picture checked before (another path)
  const found = new Map();
  for (const doc of (await db.collection('photoFingerprints').where('sha256', '==', sha256).limit(20).get()).docs) found.set(doc.id, doc.data());
  if (hash) {
    for (const [band, value] of Object.entries(bands(hash))) {
      for (const doc of (await db.collection('photoFingerprints').where(band, '==', value).limit(50).get()).docs) {
        const data = doc.data();
        if (data.hash && distance(hash, data.hash) <= SAME_PICTURE_BITS) found.set(doc.id, data);
      }
    }
  }
  const duplicates = [...found.values()].filter(d => d.path !== path).slice(0, 10)
    .map(d => ({path: d.path, kind: d.kind, ownerId: d.ownerId, label: d.label, exact: d.sha256 === sha256}));
  await db.collection('photoFingerprints').doc(checkId(path)).set({path, sha256, hash, ...(hash ? bands(hash) : {}), ...owner, at: FieldValue.serverTimestamp()});

  // ---- Google: is the picture on the internet?
  let verdict;
  if (!(await reserveScan(now))) verdict = {online: 'limit', matches: [], pages: [], bestGuess: '', note: 'This month\'s free Google checks are used up.'};
  else {
    try {
      verdict = onlineVerdict(await webDetection(bytes));
    } catch (error) {
      await releaseScan(now);
      verdict = {online: 'error', matches: [], pages: [], bestGuess: '', note: String(error.message || error).slice(0, 300)};
    }
  }
  const result = {path, ...owner, sha256, duplicates, ...verdict, checkedBy, checkedAt: FieldValue.serverTimestamp()};
  await db.collection('photoChecks').doc(checkId(path)).set(result);
  return {...result, checkedAt: new Date(now).toISOString()};
}

exports.checkPhoto = onCall(options, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true || request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
  const path = request.data?.path;
  if (typeof path !== 'string' || !CHECKABLE.test(path)) throw new HttpsError('invalid-argument', 'This photo cannot be checked.');
  return checkPhotoAt(path, request.auth.uid);
});

/// The photos of [paths] that have not been checked yet.
async function uncheckedPhotos(paths) {
  if (!paths.length) return [];
  const docs = await db.getAll(...paths.map(path => db.collection('photoChecks').doc(checkId(path))));
  return paths.filter((_, i) => !docs[i].exists);
}

exports._photoCheck = {
  checkPhotoAt, uncheckedPhotos, fingerprint, distance, onlineVerdict, describePath, checkId, monthKey, CHECKABLE, FREE_SCANS_PER_MONTH,
  setWebDetection: fn => { webDetection = fn; },
};
