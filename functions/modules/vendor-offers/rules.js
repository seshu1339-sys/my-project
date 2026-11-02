'use strict';
// Vendor Offers: the pure rules, no database. An offer has no link to plans or payments.
const DAY_MS = 86400000;
const MAX_DAYS = 30, MAX_PHOTOS = 3, MAX_RUNNING = 10, MAX_PRICE = 10000000;
const FOLDER = 'vendorOffers';

const text = value => (typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '');
const money = value => typeof value === 'number' && Number.isFinite(value) && value > 0 && value <= MAX_PRICE && Math.round(value * 100) === Number((value * 100).toFixed(6));

/// The Storage path of a photo, only when it is a download link of this vendor's own offer folder.
function photoPath(url, uid) {
  let parsed;
  try { parsed = new URL(url); } catch { return null; }
  if (parsed.protocol !== 'https:' || parsed.hostname !== 'firebasestorage.googleapis.com' || String(url).length > 2000) return null;
  const match = parsed.pathname.match(/\/o\/([^/]+)$/);
  if (!match) return null;
  let path;
  try { path = decodeURIComponent(match[1]); } catch { return null; }
  return new RegExp(`^${FOLDER}/${uid}/[A-Za-z0-9._-]+$`).test(path) ? path : null;
}

/// What a vendor may save as an offer. [days] may be left out only when [keepEnd] is true (editing an offer that is still running).
function validateOffer(data, uid, keepEnd = false) {
  const title = text(data.title);
  if (title.length < 2 || title.length > 80) throw new Error('Give the offer a name (2-80 characters).');
  const details = text(data.details);
  if (details.length > 300) throw new Error('Keep the details under 300 characters.');
  if (!money(data.offerPrice)) throw new Error('Enter a valid offer price, with at most 2 decimals.');
  const regular = data.regularPrice ?? null;
  if (regular !== null && (!money(regular) || regular <= data.offerPrice)) throw new Error('The regular price must be above the offer price.');
  const photos = Array.isArray(data.photos) ? data.photos : [];
  if (photos.length < 1 || photos.length > MAX_PHOTOS) throw new Error(`Add 1 to ${MAX_PHOTOS} photos of your own.`);
  if (new Set(photos).size !== photos.length || photos.some(url => typeof url !== 'string' || !photoPath(url, uid))) throw new Error('Upload the photos from your own vendor app.');
  const days = data.days ?? null;
  if (days === null ? !keepEnd : !Number.isInteger(days) || days < 1 || days > MAX_DAYS) throw new Error(`Choose 1 to ${MAX_DAYS} days.`);
  return {title, details, offerPrice: data.offerPrice, regularPrice: regular, photos, days};
}

/// The status a saved offer gets: live at once, unless the admin switched on approval.
const statusOnSave = approvalRequired => (approvalRequired === true ? 'pending' : 'live');

const endsAtFrom = (now, days) => now + days * DAY_MS;

/// An offer counts against the limit while it is live or waiting and its end date has not passed.
const isRunning = (offer, now) => ['live', 'pending'].includes(offer.status) && (offer.endsAt?.toMillis?.() ?? 0) > now;

module.exports = {DAY_MS, MAX_DAYS, MAX_PHOTOS, MAX_RUNNING, FOLDER, photoPath, validateOffer, statusOnSave, endsAtFrom, isRunning};
