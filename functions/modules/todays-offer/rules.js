'use strict';
// Today's Offer: the pure rules of one vendor offer, no database.
const HOUR_MS = 3600000;
const HOURS = [24, 48];
const MAX_PRICE = 10000000;
const FOLDER = 'vendorTodaysOffers';

/// The Storage path of a photo, only when it is a download link from this vendor's own folder.
function photoPath(url, uid) {
  if (typeof url !== 'string' || url.length > 2000) return null;
  let parsed;
  try { parsed = new URL(url); } catch { return null; }
  if (parsed.protocol !== 'https:' || parsed.hostname !== 'firebasestorage.googleapis.com') return null;
  const match = parsed.pathname.match(/\/o\/([^/]+)$/);
  if (!match) return null;
  let path;
  try { path = decodeURIComponent(match[1]); } catch { return null; }
  return path.startsWith(`${FOLDER}/${uid}/`) && /^[A-Za-z0-9._-]+$/.test(path.slice(`${FOLDER}/${uid}/`.length)) ? path : null;
}

/// What a vendor sends: a price and how long. The photo is checked apart, against Storage.
function validateOffer(data) {
  const {price, hours} = data;
  if (typeof price !== 'number' || !Number.isFinite(price) || price <= 0 || price > MAX_PRICE) throw new Error('Enter a valid price.');
  if (Math.round(price * 100) !== Number((price * 100).toFixed(6))) throw new Error('Enter the price with at most 2 decimals.');
  if (!HOURS.includes(hours)) throw new Error('Choose 24 or 48 hours.');
  return {price, hours};
}

/// When an offer ends: after the chosen hours, or when the plan ends if that comes first.
const offerEnd = (now, hours, planEndsAt) => Math.min(now + hours * HOUR_MS, planEndsAt);

module.exports = {HOUR_MS, FOLDER, photoPath, validateOffer, offerEnd};
