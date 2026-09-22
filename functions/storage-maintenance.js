'use strict';
// Scheduled housekeeping: expires unreviewed shop photos, runs the Special Category Exclusives
// lifecycle (notify -> auto-archive -> auto-delete), sweeps a couple of narrowly-scoped orphan
// cases, and records Storage usage for the admin. Reuses the pages()/send() helpers already
// built for offer notifications (functions/notifications.js) instead of duplicating them.
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {_internal} = require('./notifications');
const {send, pages} = _internal;
const db = getFirestore();
const DAY_MS = 86400000;
const SHOP_PHOTO_PENDING_TTL_MS = 15 * DAY_MS;
const EXCLUSIVE_ARCHIVE_TTL_MS = 15 * DAY_MS;
const ORPHAN_GRACE_MS = DAY_MS; // never delete something that might still be mid-upload

function pathFromDownloadUrl(url) {
  const match = typeof url === 'string' && url.match(/\/o\/([^?]+)/);
  return match ? decodeURIComponent(match[1]) : null;
}

// A vendor shop photo still 'pending' 15 days after submission is deleted: the object and the
// Firestore record. Ordered ascending by submittedAt, so the loop can stop at the first doc
// that's still within the window.
async function expireShopPhotos(now) {
  const bucket = getStorage().bucket();
  const cutoff = now - SHOP_PHOTO_PENDING_TTL_MS;
  for await (const doc of pages(db.collection('vendorShopPhotos').where('status', '==', 'pending').orderBy('submittedAt'))) {
    const data = doc.data();
    const submittedAt = data.submittedAt?.toMillis?.() ?? 0;
    if (submittedAt > cutoff) break;
    if (data.path) await bucket.file(data.path).delete({ignoreNotFound: true});
    await doc.ref.delete();
  }
}

// Exclusive items: notify the owning vendor once as an item nears expiry, auto-archive
// (active:false) the moment it expires, and permanently delete anything left archived for 15 days.
async function processExclusiveExpiry(now) {
  const nowIso = new Date(now).toISOString();
  const business = (await db.collection('settings').doc('business').get()).data() || {};
  const noticeDaysSetting = Number(business.exclusiveExpiryNoticeDays);
  const noticeMs = (Number.isFinite(noticeDaysSetting) && noticeDaysSetting > 0 ? noticeDaysSetting : 2) * DAY_MS;
  const noticeIso = new Date(now + noticeMs).toISOString();

  for await (const doc of pages(db.collection('products').where('isExclusive', '==', true).where('active', '==', true).where('expiresAt', '>=', nowIso).where('expiresAt', '<=', noticeIso))) {
    const data = doc.data();
    if (data.notifiedExpiryAt || !data.ownerId) continue;
    await send(data.ownerId, `exclusiveExpiring:${doc.id}`, {title: 'Exclusive item expiring soon', body: `"${data.name}" will expire soon. Manage it or extend it in your vendor studio.`}, {type: 'exclusiveExpiring', productId: doc.id});
    await doc.ref.update({notifiedExpiryAt: FieldValue.serverTimestamp()});
  }

  for await (const doc of pages(db.collection('products').where('isExclusive', '==', true).where('active', '==', true).where('expiresAt', '<=', nowIso))) {
    await doc.ref.update({active: false, archivedAt: nowIso});
  }

  const bucket = getStorage().bucket();
  const archivedCutoffIso = new Date(now - EXCLUSIVE_ARCHIVE_TTL_MS).toISOString();
  for await (const doc of pages(db.collection('products').where('isExclusive', '==', true).where('active', '==', false).where('archivedAt', '<=', archivedCutoffIso))) {
    const path = pathFromDownloadUrl(doc.data().imageUrl);
    if (path) await bucket.file(path).delete({ignoreNotFound: true});
    await doc.ref.delete();
  }
}

// A shop-photo Storage object with no matching Firestore record at all (e.g. the upload
// succeeded but submitShopPhoto never ran) is an orphan once past the upload grace period.
async function sweepOrphanShopPhotos(now) {
  const cutoff = now - ORPHAN_GRACE_MS;
  const [files] = await getStorage().bucket().getFiles({prefix: 'vendorShopPhotos/'});
  for (const file of files) {
    const created = Date.parse(file.metadata?.timeCreated || '');
    if (!Number.isFinite(created) || created > cutoff) continue;
    const match = file.name.match(/^vendorShopPhotos\/([^/]+)\/shopPhoto([12])$/);
    if (!match) continue;
    const [, uid, slot] = match;
    const exists = (await db.collection('vendorShopPhotos').doc(`${uid}_${slot}`).get()).exists;
    if (!exists) await file.delete({ignoreNotFound: true}).catch(() => {});
  }
}

// Same idea for vendorProducts/: an object no product's imageUrl points to, past the grace period.
async function sweepOrphanVendorProducts(now) {
  const referenced = new Set();
  for await (const doc of pages(db.collection('products').orderBy('__name__'))) {
    const path = pathFromDownloadUrl(doc.data().imageUrl);
    if (path) referenced.add(path);
  }
  const cutoff = now - ORPHAN_GRACE_MS;
  const [files] = await getStorage().bucket().getFiles({prefix: 'vendorProducts/'});
  for (const file of files) {
    if (referenced.has(file.name)) continue;
    const created = Date.parse(file.metadata?.timeCreated || '');
    if (!Number.isFinite(created) || created > cutoff) continue;
    await file.delete({ignoreNotFound: true}).catch(() => {});
  }
}

exports.dailyStorageMaintenance = onSchedule({schedule: 'every 24 hours', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 540}, async () => {
  const now = Date.now();
  await expireShopPhotos(now);
  await processExclusiveExpiry(now);
  await sweepOrphanShopPhotos(now);
  await sweepOrphanVendorProducts(now);
});

// Lighter cadence: a full bucket listing is more than a daily job needs.
exports.weeklyStorageUsage = onSchedule({schedule: 'every monday 03:00', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 540}, async () => {
  const [files] = await getStorage().bucket().getFiles();
  let bytesUsed = 0;
  for (const file of files) bytesUsed += Number(file.metadata?.size) || 0;
  await db.collection('analyticsTotals').doc('storageUsage').set({bytesUsed, objectCount: files.length, updatedAt: FieldValue.serverTimestamp()});
});
