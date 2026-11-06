'use strict';
// The rules of a vendor's "sudden offer" alert, with no database in them.
//
// A paid vendor who adds an offer (Vendor Offers module) may ask for an alert. It reaches customers within the vendor's plan km of the
// shop (owner, 7 Nov 2026: no separate alert km). The alert goes once per offer, to every customer with notifications on whose last
// known location is inside that circle; a customer outside it, or with no known location, gets nothing. One alert per vendor a day.
const LEGACY_RADII = [25, 50];
const DEFAULT_PLAN_KM = 25;
const VENDOR_ALERT_GAP_MS = 24 * 60 * 60 * 1000;

const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);

function distanceKm(lat1, lon1, lat2, lon2) {
  const rad = d => (d * Math.PI) / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lon2 - lon1) / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/// Whether a saved offer asks for an alert (alert: true; offers saved before 7 Nov 2026 kept 25 or 50 km instead).
const wantsAlert = offer => offer?.alert === true || (offer?.alert === undefined && LEGACY_RADII.includes(offer?.alertRadiusKm));

/// How far the alert reaches: the km of the vendor's running plan (vendorPremium.radiusKm).
const planKm = premium => (typeof premium?.radiusKm === 'number' && premium.radiusKm >= 1 ? premium.radiusKm : DEFAULT_PLAN_KM);

/// A place {lat, lng} from a document with latitude / longitude, or null.
function placeOf(data) {
  const lat = num(data?.latitude), lng = num(data?.longitude);
  return lat === null || lng === null || (lat === 0 && lng === 0) ? null : {lat, lng};
}

/// How far the customer is from the shop, or null when they are outside the circle or have no known location.
function reach(shop, subscriber, radiusKm) {
  const at = placeOf(subscriber);
  if (!at || !shop) return null;
  const km = distanceKm(shop.lat, shop.lng, at.lat, at.lng);
  return km <= radiusKm ? km : null;
}

const rupees = v => (Number.isInteger(v) ? `₹${v}` : `₹${Number(v).toFixed(2)}`);

/// What the customer reads: the shop, the offer and its price, and how far.
function alertCopy(offer, km) {
  const was = num(offer.regularPrice) ? ` (was ${rupees(offer.regularPrice)})` : '';
  const far = km < 1 ? 'less than 1 km away' : `${Math.round(km)} km away`;
  return {
    title: `Offer near you: ${offer.shopName || 'a shop'}`.slice(0, 100),
    body: `${offer.title}: ${rupees(offer.offerPrice)}${was} • ${far}. Tap to see the shop and the way.`.slice(0, 240),
  };
}

/// Whether the vendor may send another alert now (one a day).
const vendorMayAlert = (lastAt, now) => !lastAt || now - lastAt >= VENDOR_ALERT_GAP_MS;

module.exports = {DEFAULT_PLAN_KM, VENDOR_ALERT_GAP_MS, distanceKm, wantsAlert, planKm, placeOf, reach, alertCopy, vendorMayAlert};
