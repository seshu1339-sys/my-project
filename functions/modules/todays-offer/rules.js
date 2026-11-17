'use strict';
// Today's Offer: the pure rules of one vendor offer, no database.
const HOUR_MS = 3600000;
const HOURS = [24, 48];
const MAX_PRICE = 10000000;
const FOLDER = 'vendorTodaysOffers';

/// Google's Storage address; while testing in the local Firebase emulators (FUNCTIONS_EMULATOR=true) also the Storage emulator's.
/// Kept inside this module so the module stays independent.
function storageHost(parsed) {
  if (parsed.protocol === 'https:' && parsed.hostname === 'firebasestorage.googleapis.com') return true;
  return process.env.FUNCTIONS_EMULATOR === 'true' && parsed.protocol === 'http:' && ['127.0.0.1', 'localhost', '10.0.2.2'].includes(parsed.hostname) && parsed.port === '9199';
}

/// The Storage path of a photo, only when it is a download link from this vendor's own folder.
function photoPath(url, uid) {
  if (typeof url !== 'string' || url.length > 2000) return null;
  let parsed;
  try { parsed = new URL(url); } catch { return null; }
  if (!storageHost(parsed)) return null;
  const match = parsed.pathname.match(/\/o\/([^/]+)$/);
  if (!match) return null;
  let path;
  try { path = decodeURIComponent(match[1]); } catch { return null; }
  return path.startsWith(`${FOLDER}/${uid}/`) && /^[A-Za-z0-9._-]+$/.test(path.slice(`${FOLDER}/${uid}/`.length)) ? path : null;
}

/// How long a box may show, in days (owner, 7 Nov 2026): 1 week, 1 month, 2 months or 3 months.
const DAY_MS = 86400000;
const DAY_CHOICES = [7, 30, 60, 90];
/// How many Today's Offers boxes a plan gives when the admin has not set the plan's own number: Silver 1, Gold 3, Premium 5.
const DEFAULT_BOXES = {silver: 1, gold: 2, platinum: 4, diamond: 6, premium: 5};
const MAX_BOXES = 20;

/// The boxes of a vendor's running plan (vendorPremium.offerBoxes, copied from the plan), else the default of the plan's kind.
function boxesOf(premium) {
  if (Number.isInteger(premium?.offerBoxes) && premium.offerBoxes >= 0 && premium.offerBoxes <= MAX_BOXES) return premium.offerBoxes;
  return DEFAULT_BOXES[premium?.tier] ?? DEFAULT_BOXES.premium;
}

const ID = /^[A-Za-z0-9_-]{1,128}$/;

/// What a vendor sends (owner, 13 Nov 2026): exactly one of
///   productId      one of their own items (its name and photo),
///   libraryItemId  an item from the catalog (the Product Image Library: its name and stock photo),
///   photoName      their own photo, uploaded first to vendorTodaysOffers/<uid>/<photoName>, with the item's name (checked by Claude Haiku);
/// the offer price, an optional short text (note), optionally how long (days; none = while the plan runs) and which box (1 to the plan's
/// number).
const NOTE_MAX = 60;
function validateOffer(data, boxes) {
  const given = key => data[key] !== undefined && data[key] !== null && data[key] !== '';
  const sources = ['productId', 'libraryItemId', 'photoName'].filter(given);
  if (sources.length !== 1) throw new Error('Choose one of your items, an item from the catalog, or upload a photo.');
  const offer = {};
  if (given('productId')) {
    if (typeof data.productId !== 'string' || !ID.test(data.productId)) throw new Error('Choose one of your items.');
    offer.productId = data.productId;
  } else if (given('libraryItemId')) {
    if (typeof data.libraryItemId !== 'string' || !ID.test(data.libraryItemId)) throw new Error('Choose an item from the catalog.');
    offer.libraryItemId = data.libraryItemId;
  } else {
    if (typeof data.photoName !== 'string' || !/^[A-Za-z0-9._-]{1,100}$/.test(data.photoName)) throw new Error('Upload the photo again.');
    const name = typeof data.name === 'string' ? data.name.trim().replace(/\s+/g, ' ') : '';
    if (name.length < 2 || name.length > 40) throw new Error('Enter the item name (2 to 40 letters).');
    offer.photoName = data.photoName;
    offer.name = name;
  }
  const {price} = data;
  if (typeof price !== 'number' || !Number.isFinite(price) || price <= 0 || price > MAX_PRICE) throw new Error('Enter a valid price.');
  if (Math.round(price * 100) !== Number((price * 100).toFixed(6))) throw new Error('Enter the price with at most 2 decimals.');
  const days = data.days ?? null;
  if (days !== null && !DAY_CHOICES.includes(days)) throw new Error('Choose 1 week, 1 month, 2 months or 3 months, or leave it to run with your plan.');
  const note = data.note === undefined || data.note === null ? '' : data.note;
  if (typeof note !== 'string' || note.trim().length > NOTE_MAX) throw new Error(`Keep the offer text under ${NOTE_MAX} letters.`);
  const slot = data.slot ?? null;
  if (slot !== null && (!Number.isInteger(slot) || slot < 1 || slot > boxes)) throw new Error(`Choose box 1 to ${boxes}.`);
  return {...offer, price, days, note: note.trim().replace(/\s+/g, ' '), slot};
}

/// When an offer ends: after the chosen days, or when the plan ends if that comes first. No days: when the plan ends (owner, 13 Nov 2026:
/// a Today's Offer stays live while the plan runs).
const offerEnd = (now, days, planEndsAt) => (days === null || days === undefined ? planEndsAt : Math.min(now + days * DAY_MS, planEndsAt));

/// The document of a vendor's box.
const boxId = (uid, slot) => `${uid}_${slot}`;

module.exports = {NOTE_MAX, HOUR_MS, DAY_MS, DAY_CHOICES, DEFAULT_BOXES, MAX_BOXES, FOLDER, photoPath, validateOffer, offerEnd, boxesOf, boxId};
