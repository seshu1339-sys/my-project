'use strict';
// The rules of the Staff Area System, with no database in them.
//
// The admin gives every town a radius (1, 2, 3 or 5 km, or any other: big cities small, small towns bigger) and makes named areas in
// it on a map ("Narsipatnam Main Bazaar" = a centre point + the town's radius). Areas never overlap. An area is Free, Pending (a staff
// member chose it and waits for approval; nobody else can take it) or Booked. One staff member has one area, one area one staff member.
// A staff member claims a free area only while standing inside it with GPS on, and only after accepting the Terms & Conditions.
//
// Work rules (owner, 6 Nov 2026), the same for every staff member and set by the admin:
// - Monthly targets: live photos, vendor registrations (linked) and paid-vendor registrations. A month counts only when its target is
//   complete.
// - Rate updates: a staff member updates the rates of the shops in their area (Today's Offers with a live camera photo, taken within
//   100 m of the shop with real GPS) on at least RATE_DAYS a week (default 4). Days off beyond the week's allowance (7 - RATE_DAYS) are
//   missed days; a day without any rate update (not using the app) is a day off.
// - MAX_MISSED missed days in a month (default 7) stop the account. The warning comes ONE DAY BEFORE (owner, 7 Nov 2026): on the
//   morning of the day that, if it is missed too, stops the account, so the staff member can still update rates that day (and again at
//   5 PM if they have not yet). The area is free again after a stop, and the vendors of the area stay live.
// - Staff never choose dates for an offer (owner, 7 Nov 2026): a staff rate update is that day's rate and ends at midnight. How long a
//   vendor's own offers show is the vendor's choice, in the vendor app.
// The staff hexagon grid (functions/hex-grid.js, a shared root file): a hexagon area holds exactly the places of its cell.
const hexGrid = require('../../hex-grid');
const B = require('./blocks');
const IST = 19800000;
const DAY_MS = 86400000;
const RADIUS_OPTIONS = [1, 2, 3, 5];
// Targets (owner, 7 Nov 2026): daily, weekly and monthly, each for live photos, shops visited (a shop with a verified live-photo rate
// update), new vendors linked and new paid (Premium) vendors. 0 = no target for that period. The month counts only when every monthly
// target is complete.
const PERIODS = ['daily', 'weekly', 'monthly'];
const MEASURES = {Photo: 'photos', Shop: 'shops', Vendor: 'vendors', PaidVendor: 'paidVendors'};
const targetKey = (period, measure) => `${period}${measure}Target`;
const DEFAULTS = {
  dailyPhotoTarget: 0, dailyShopTarget: 0, dailyVendorTarget: 0, dailyPaidVendorTarget: 0,
  weeklyPhotoTarget: 0, weeklyShopTarget: 0, weeklyVendorTarget: 0, weeklyPaidVendorTarget: 0,
  monthlyPhotoTarget: 100, monthlyShopTarget: 0, monthlyVendorTarget: 10, monthlyPaidVendorTarget: 2,
  rateDaysPerWeek: 4, maxMissedDays: 7,
};
// A live photo must be taken within this distance of the shop, and sent within MAX_PHOTO_AGE_MS of being taken.
const PHOTO_MAX_METRES = 100;
const MAX_PHOTO_AGE_MS = 10 * 60 * 1000;
const MAX_GPS_ACCURACY_METRES = 100;

// The Terms & Conditions until the admin writes their own (Admin > Staff Areas > Settings). Never shown in a public or marketing screen.
const DEFAULT_TERMS = [
  'LOCAMARKET staff Terms & Conditions',
  '1. There is no fixed salary. You earn a commission based on your work.',
  '2. One area per staff member. You work only in the area you registered.',
  "3. You add only Today's Offers for the shops in your area. You never change a vendor's profile, photos, items or normal prices.",
  '4. You update the rates of the shops in your area on the minimum number of days every week, each with a live camera photo taken at the shop (within 100 metres, with real GPS). Photos sent from anywhere else never count.',
  '5. You complete the targets for the day, the week and the month: live photos, shops visited, new vendors and new paid vendors. A month counts only when its monthly targets are complete.',
  '6. Days without rate updates beyond the weekly allowance are missed days. When the allowed number of missed days is reached, your staff ID is deactivated automatically and your area is given to another person. You are warned one day before.',
  '7. LOCAMARKET can change these rules at any time.',
  "8. Your area is one hexagon cell, set automatically from where you stand: 1 km in dense cities, 2 km in towns, 5 km in villages (by how many people live there). You can register a cell only while standing inside it with GPS on, and only if it is free. One cell per staff member; a cell is never shared.",
  "9. You must be local: your home must be within 5 km of the centre of your cell. If your home is farther, you cannot register that cell. Your home address may be checked before approval.",
  "10. If your staff ID is cancelled, it is closed for good and never given to anyone again. Your cell becomes free for a new staff member, and the vendors linked to you move to LOCAMARKET.",
].join('\n');

const text = v => (typeof v === 'string' ? v.trim().replace(/\s+/g, ' ') : '');
const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);

/// "Krishna Bazar (Narsipatnam)" is in Narsipatnam; the same town however it is written.
function townKey(town) {
  const bracket = String(town || '').match(/\(([^)]+)\)/);
  return String(bracket ? bracket[1] : town || '').trim().toLowerCase().replace(/\s+/g, ' ').replace(/[^a-z0-9 ]/g, '').replace(/ /g, '-');
}

function distanceKm(lat1, lon1, lat2, lon2) {
  const rad = d => (d * Math.PI) / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lon2 - lon1) / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/// A town's radius: one of the options or any other between 0.2 and 50 km (one decimal).
function validateRadius(value) {
  const r = num(value);
  if (r === null || r < 0.2 || r > 50) throw Error('Choose a radius of 1, 2, 3 or 5 km, or enter another between 0.2 and 50 km.');
  return Math.round(r * 10) / 10;
}

function validateTown(data = {}) {
  const town = text(data.town);
  if (town.length < 2 || town.length > 60) throw Error('Enter the town name.');
  return {town, townKey: townKey(town), radiusKm: validateRadius(data.radiusKm)};
}

function validCoordinate(lat, lng) {
  return num(lat) !== null && num(lng) !== null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0);
}

function validateArea(data = {}) {
  const name = text(data.name);
  if (name.length < 2 || name.length > 80) throw Error('Give the area a name (2-80 characters), like "Narsipatnam Main Bazaar".');
  if (!validCoordinate(data.latitude, data.longitude)) throw Error('Tap the map to put the centre of the area.');
  const town = text(data.town);
  if (town.length < 2) throw Error('Choose the town.');
  return {name, town, townKey: townKey(town), latitude: data.latitude, longitude: data.longitude};
}

/// Two areas overlap when their circles touch: the distance between the centres is under the two radii together.
const overlaps = (a, b) => distanceKm(a.latitude, a.longitude, b.latitude, b.longitude) < a.radiusKm + b.radiusKm;

/// Whether a place is inside an area: its hexagon cell (owner, 13 Nov 2026), or the circle of an older area.
const inside = (area, lat, lng) => {
  if (!validCoordinate(lat, lng)) return false;
  if (area.hexCell) return hexGrid.contains(area.hexCell, lat, lng);
  return distanceKm(area.latitude, area.longitude, lat, lng) <= area.radiusKm;
};

/// The India date of a moment: "2026-11-06".
const istDay = ms => new Date(ms + IST).toISOString().slice(0, 10);
/// The first and the last moment of an India date.
const dayStart = day => Date.parse(`${day}T00:00:00Z`) - IST;
const dayEnd = day => dayStart(day) + DAY_MS - 1;
const addDays = (day, n) => istDay(dayStart(day) + n * DAY_MS + 1);

const whole = (data, out, key, min, max, message) => {
  if (data[key] === undefined) return;
  if (!Number.isInteger(data[key]) || data[key] < min || data[key] > max) throw Error(message);
  out[key] = data[key];
};

function validateSettings(data = {}) {
  const out = {};
  const words = {Photo: 'live photos', Shop: 'shops visited', Vendor: 'new vendors', PaidVendor: 'new paid vendors'};
  const when = {daily: 'a day', weekly: 'a week', monthly: 'a month'};
  for (const period of PERIODS) {
    for (const measure of Object.keys(MEASURES)) {
      whole(data, out, targetKey(period, measure), 0, 10000, `Enter the target for ${words[measure]} ${when[period]} as a whole number from 0 to 10000 (0 = no target).`);
    }
  }
  whole(data, out, 'rateDaysPerWeek', 1, 7, 'Enter 1 to 7 rate days a week.');
  whole(data, out, 'maxMissedDays', 1, 31, 'Enter 1 to 31 missed days (the account stops on that day).');
  // The automatic area size: buildings per km2 -> radius (owner, 7 Nov 2026).
  if (data.densityBands !== undefined) out.densityBands = B.validateBands(data.densityBands);
  if (data.terms !== undefined) {
    const terms = typeof data.terms === 'string' ? data.terms.trim() : '';
    if (terms.length < 20 || terms.length > 8000) throw Error('Write the Terms & Conditions (20 to 8000 characters).');
    out.terms = terms;
  }
  if (!Object.keys(out).length) throw Error('Nothing to save.');
  return out;
}

const settingsOf = data => ({
  ...Object.fromEntries(Object.entries(DEFAULTS).map(([k, v]) => [k, Number.isInteger(data?.[k]) ? data[k] : v])),
  terms: typeof data?.terms === 'string' && data.terms.trim() ? data.terms : DEFAULT_TERMS,
  densityBands: B.bandsOf(data?.densityBands),
});

/// The Monday (India date) of the week of [day].
function weekOf(day) {
  const dow = new Date(`${day}T00:00:00Z`).getUTCDay(); // 0 Sunday ... 6 Saturday
  return addDays(day, -((dow + 6) % 7));
}

/// What a day without rate updates is: a free day off (within the week's allowance) or a missed day.
const dayOff = (offDaysUsedThisWeek, rateDaysPerWeek) => (offDaysUsedThisWeek < 7 - rateDaysPerWeek ? 'off' : 'missed');

/// A live photo is accepted only when it was taken with real GPS (not a mock location app), accurately, within 100 m of the shop, and
/// sent soon after it was taken. Returns why not, or null.
function livePhotoProblem({latitude, longitude, accuracy, mocked, takenAt}, shop, now) {
  if (mocked !== false) return 'Fake GPS (a mock location app) is not allowed. Turn it off and take the photo again at the shop.';
  if (!validCoordinate(latitude, longitude)) return 'Turn on GPS and take the photo at the shop.';
  if (typeof accuracy !== 'number' || accuracy > MAX_GPS_ACCURACY_METRES) return 'Your GPS is not exact enough. Wait for a better signal at the shop and try again.';
  if (!validCoordinate(shop?.latitude, shop?.longitude)) return 'This shop has no map location, so its rates cannot be updated.';
  const metres = distanceKm(latitude, longitude, shop.latitude, shop.longitude) * 1000;
  if (metres > PHOTO_MAX_METRES) return `You are ${Math.round(metres)} m from the shop. Go to the shop (within ${PHOTO_MAX_METRES} m) and take the photo there.`;
  if (typeof takenAt !== 'number' || takenAt > now + 60000 || now - takenAt > MAX_PHOTO_AGE_MS) return 'Take a new live photo: this one is too old.';
  return null;
}

/// How far a target is: done / target, and whether it is complete (a target of 0 is always complete).
const targetProgress = (done, target) => ({done, target, complete: done >= target});

/// Every target for a period and its progress: {photos, shops, vendors, paidVendors}, each {done, target, complete}.
function periodTargets(settings, period, counts) {
  const out = {};
  for (const [measure, name] of Object.entries(MEASURES)) out[name] = targetProgress(counts[name] || 0, settings[targetKey(period, measure)] || 0);
  return out;
}

const money = v => num(v) !== null && v > 0 && v <= 10000000 && Math.abs(v * 100 - Math.round(v * 100)) < 1e-6;

/// What a staff member may save as a Today's Offer: a shop, an item from the admin's list, the normal price and a lower offer price.
/// It is always today's rate (staff choose no dates); any date sent is ignored.
function validateStaffOffer(data = {}, today) {
  if (typeof data.shopId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(data.shopId)) throw Error('Choose the shop.');
  if (typeof data.libraryItemId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(data.libraryItemId)) throw Error('Choose the item from the list.');
  if (!money(data.regularPrice)) throw Error('Enter the normal price.');
  if (!money(data.offerPrice)) throw Error('Enter the offer price.');
  if (data.offerPrice >= data.regularPrice) throw Error('The offer price must be lower than the normal price.');
  return {shopId: data.shopId, libraryItemId: data.libraryItemId, regularPrice: data.regularPrice, offerPrice: data.offerPrice, validDate: today};
}

/// A day's result for an area.
const dayResult = (staffCount, vendorCount, target) => ({staffCount, vendorCount, total: staffCount + vendorCount, target, met: staffCount + vendorCount >= target});

/// What a missed day leads to: the account stops on the [maxMissed]-th missed day of a month.
const missedOutcome = (missed, maxMissed) => (missed >= maxMissed ? 'deactivate' : 'missed');

/// Whether today is the last chance (owner, 7 Nov 2026: warn ONE DAY BEFORE the stop, before the day is missed): a day without rate
/// updates today would be a missed day (the week's days off are used up) and would reach [maxMissed].
const lastChance = (missedThisMonth, maxMissed, offDaysUsedThisWeek, rateDaysPerWeek) =>
  dayOff(offDaysUsedThisWeek, rateDaysPerWeek) === 'missed' && missedThisMonth + 1 >= maxMissed;

module.exports = {
  IST, DAY_MS, RADIUS_OPTIONS, DEFAULTS, DEFAULT_TERMS, lastChance,
  townKey, distanceKm, validateRadius, validateTown, validateArea, validCoordinate, overlaps, inside,
  istDay, dayStart, dayEnd, addDays, validateSettings, settingsOf, validateStaffOffer, dayResult, missedOutcome,
  weekOf, dayOff, livePhotoProblem, targetProgress, periodTargets, PERIODS, MEASURES, targetKey, PHOTO_MAX_METRES, MAX_PHOTO_AGE_MS,
};
