'use strict';
// Safety net for photos: the apps already shrink every photo to WebP before uploading (lib/services/image_compress.dart),
// but an older app version, another browser or a direct upload may still store a big JPEG/PNG. Whenever one lands in
// a photo folder, it is shrunk (longest side 1600 px) and saved again as WebP at the same path, keeping its download link.
const {onObjectFinalized} = require('firebase-functions/v2/storage');
const {getStorage} = require('firebase-admin/storage');

// Only the folders the apps upload photos to (never anything else in the bucket).
const PHOTO_FOLDERS = ['catalog/', 'quickItems/', 'fieldSubmissions/', 'fieldStaffApplications/', 'vendorApplications/', 'vendorProducts/', 'vendorShopPhotos/'];
const CONVERTIBLE = new Set(['image/jpeg', 'image/jpg', 'image/png']);
// Every photo is kept on phones and browsers for 30 days (free-limit plan, owner OK 17 Nov 2026): photos are downloaded again only when
// they change (each upload has a new name or a new download link), so far fewer downloads from the bucket. Public photos may also be
// kept by shared caches; private ones (ID and application photos) only on the person's own device.
const PUBLIC_PHOTOS = ['catalog/', 'vendorProducts/', 'vendorOffers/', 'vendorTodaysOffers/', 'wholesaleOffers/', 'vendorShopPhotos/', 'vendorItemPhotos/', 'staffOfferPhotos/'];
const PRIVATE_PHOTOS = ['vendorApplications/', 'providerApplications/', 'fieldStaffApplications/', 'fieldSubmissions/', 'staffAdditions/', 'quickItems/'];
const MONTH = 2592000;
/// The cache rule of a stored file by its folder, or null (not a photo folder: left as it is).
const cacheFor = name => (PUBLIC_PHOTOS.some(f => name.startsWith(f)) ? `public, max-age=${MONTH}` : PRIVATE_PHOTOS.some(f => name.startsWith(f)) ? `private, max-age=${MONTH}` : null);
const MAX_SIDE = 1600, QUALITY = 80, MAX_INPUT_BYTES = 25 * 1024 * 1024;

/// The WebP version of a photo: rotated upright, longest side at most MAX_SIDE, never enlarged.
// sharp is loaded on first use, so starting the functions (and deploying them) stays fast.
const toWebp = buffer => require('sharp')(buffer, {failOn: 'none'}).rotate().resize({width: MAX_SIDE, height: MAX_SIDE, fit: 'inside', withoutEnlargement: true}).webp({quality: QUALITY}).toBuffer();

/// Converts one stored photo. Returns {status: 'converted' | 'skipped', ...}; never throws for a photo it cannot use.
async function optimizeObject(bucket, name, contentType) {
  const cache = cacheFor(name);
  const convertible = PHOTO_FOLDERS.some(folder => name.startsWith(folder)) && CONVERTIBLE.has(String(contentType || '').toLowerCase());
  if (!convertible) {
    if (!cache) return {status: 'skipped', reason: 'not a photo folder'};
    // Not converted (already WebP, or a folder that is never converted): only the 30-day cache rule, once.
    const file = bucket.file(name);
    const [metadata] = await file.getMetadata();
    if (metadata.cacheControl === cache) return {status: 'skipped', reason: 'cache already set'};
    await file.setMetadata({cacheControl: cache});
    return {status: 'cached'};
  }
  const file = bucket.file(name);
  const [metadata] = await file.getMetadata();
  // Left as it is: still gets the 30-day cache rule.
  const keep = async reason => {
    if (cache && metadata.cacheControl !== cache) await file.setMetadata({cacheControl: cache});
    return {status: 'skipped', reason};
  };
  if (metadata.metadata?.optimized === 'webp') return keep('already optimized');
  if (Number(metadata.size) > MAX_INPUT_BYTES) return keep('too large');
  const [original] = await file.download();
  let webp;
  try { webp = await toWebp(original); }
  catch (error) { return keep(`unreadable image: ${String(error.message).slice(0, 80)}`); }
  // A tiny JPEG can come out bigger; keep the original then (a PNG with transparency is always worth converting).
  if (webp.length >= original.length && /jpe?g/i.test(contentType)) return keep('not smaller');
  await file.save(webp, {
    resumable: false,
    metadata: {
      contentType: 'image/webp',
      cacheControl: cache || metadata.cacheControl,
      // keeps firebaseStorageDownloadTokens, so links already handed out keep working
      metadata: {...metadata.metadata, optimized: 'webp'},
    },
  });
  return {status: 'converted', before: original.length, after: webp.length};
}

exports.optimizeUploadedImage = onObjectFinalized({region: 'asia-south1', memory: '512MiB', timeoutSeconds: 120, maxInstances: 5}, async event => {
  const {bucket, name, contentType} = event.data;
  const result = await optimizeObject(getStorage().bucket(bucket), name, contentType);
  if (result.status === 'converted') console.log('Photo converted to WebP', {name, before: result.before, after: result.after});
});

exports._imageWebp = {optimizeObject, toWebp, cacheFor, PHOTO_FOLDERS, PUBLIC_PHOTOS, PRIVATE_PHOTOS};
