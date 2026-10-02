'use strict';
const {scryptSync, randomBytes, timingSafeEqual} = require('node:crypto');
function hashPin(pin, salt = randomBytes(32).toString('hex')) {
  return {salt, hash: scryptSync(pin, salt, 64).toString('hex')};
}
function verifyPin(pin, record) {
  if (!record || typeof record.salt !== 'string' || typeof record.hash !== 'string') return false;
  const expected = Buffer.from(record.hash, 'hex');
  const actual = scryptSync(pin, record.salt, 64);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}
// A flat, business-wide delivery/service charge, waived above an optional
// order total threshold. Unset or non-positive values mean no charge at
// all, preserving prior behaviour for businesses that never configure it.
function deliveryCharge(subtotal, business) {
  const fee = Number(business?.deliveryFee);
  if (!Number.isFinite(fee) || fee <= 0) return 0;
  const threshold = Number(business?.freeDeliveryAbove);
  if (Number.isFinite(threshold) && threshold > 0 && subtotal >= threshold) return 0;
  return Math.round(fee * 100) / 100;
}
function quote(items, products, pincode, business = {}, now = new Date()) {
  if (!Array.isArray(items) || !items.length || items.length > 50) throw Error('Choose 1–50 items');
  const seen = new Set();
  const lines = items.map((item, i) => {
    if (typeof item.productId !== 'string' || seen.has(item.productId) || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 99) throw Error('Invalid quantity or duplicate item');
    seen.add(item.productId);
    const p = products[i];
    if (!p || p.active !== true || p.stock < item.quantity || !Number.isFinite(p.stock)) throw Error('An item is no longer available');
    if ((p.startsAt && new Date(p.startsAt) > now) || (p.endsAt && new Date(p.endsAt) <= now)) throw Error('An item is no longer available');
    const price = p.prices && Object.hasOwn(p.prices, pincode) ? p.prices[pincode] : p.price;
    if (!Number.isFinite(price) || price < 0 || price > 10000000) throw Error('Invalid item price');
    return {productId: item.productId, name: p.name, kind: p.kind, shopId: p.shopId, quantity: item.quantity, unitPrice: Math.round(price * 100) / 100};
  });
  const subtotal = lines.reduce((sum, l) => sum + Math.round(l.unitPrice * 100) * l.quantity, 0) / 100;
  const deliveryFee = deliveryCharge(subtotal, business);
  const total = Math.round((subtotal + deliveryFee) * 100) / 100;
  return {lines, subtotal, deliveryFee, total};
}
function distanceKm(latitudeA, longitudeA, latitudeB, longitudeB) {
  const toRadians = value => value * Math.PI / 180;
  const dLat = toRadians(latitudeB - latitudeA);
  const dLng = toRadians(longitudeB - longitudeA);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRadians(latitudeA)) * Math.cos(toRadians(latitudeB))
    * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
function validCoordinate(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= -180 && value <= 180;
}
// ---- Promotion geo-targeting (mirrors lib/domain/catalog.dart field-for-field,
// so client and server always agree on which customers a promotion reaches).
function toNumber(value, fallback = 0) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') { const n = Number(value); if (Number.isFinite(n)) return n; }
  return fallback;
}
function toText(value, fallback = '') {
  if (value === undefined || value === null || value === '') return fallback;
  return String(value);
}
function parseRectangleField(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const rectangle = {};
  for (const key of ['north', 'south', 'east', 'west']) {
    const value = raw[key];
    if (typeof value !== 'number' || !Number.isFinite(value)) return null;
    rectangle[key] = value;
  }
  return rectangle;
}
function parsePolygonField(raw) {
  if (!Array.isArray(raw)) return null;
  const ring = [];
  for (const point of raw) {
    if (!point || typeof point !== 'object') return null;
    const lat = point.lat, lng = point.lng;
    if (typeof lat !== 'number' || typeof lng !== 'number') return null;
    ring.push([lat, lng]);
  }
  return ring.length >= 3 ? ring : null;
}
function pointInRectangle(lat, lng, rectangle) {
  return lat <= rectangle.north && lat >= rectangle.south && lng <= rectangle.east && lng >= rectangle.west;
}
function pointInPolygon(lat, lng, ring) {
  if (ring.length < 3) return false;
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [latI, lngI] = ring[i], [latJ, lngJ] = ring[j];
    if ((latI > lat) !== (latJ > lat) && lng < (lngJ - lngI) * (lat - latI) / (latJ - latI) + lngI) inside = !inside;
  }
  return inside;
}
// Does this promotion reach a customer at the given pincode/coordinates?
// `geoShape` absent means 'circle', reproducing pre-shape-targeting behaviour
// byte-for-byte for every promotion saved before this feature existed.
function promotionMatchesLocation(promotion, {customerPincode, customerLatitude, customerLongitude} = {}) {
  const data = promotion || {};
  const targetPincode = toText(data.targetPincode);
  const geoShape = toText(data.geoShape, 'circle');
  const targetLatitude = toNumber(data.targetLatitude);
  const targetLongitude = toNumber(data.targetLongitude);
  const hasRadiusTarget = geoShape === 'circle' && (targetLatitude !== 0 || targetLongitude !== 0);
  const rectangle = geoShape === 'rectangle' ? parseRectangleField(data.targetRectangle) : null;
  const polygon = geoShape === 'polygon' ? parsePolygonField(data.targetPolygon) : null;
  const hasShapeTarget = hasRadiusTarget || rectangle !== null || polygon !== null;
  if (!targetPincode && !hasShapeTarget) return true;
  if (hasShapeTarget) {
    if (typeof customerLatitude !== 'number' || typeof customerLongitude !== 'number') return false;
    if (rectangle) return pointInRectangle(customerLatitude, customerLongitude, rectangle);
    if (polygon) return pointInPolygon(customerLatitude, customerLongitude, polygon);
    const radiusKm = toNumber(data.targetRadiusKm) > 0 ? toNumber(data.targetRadiusKm) : 10;
    return distanceKm(customerLatitude, customerLongitude, targetLatitude, targetLongitude) <= radiusKm;
  }
  return Boolean(customerPincode) && customerPincode === targetPincode;
}
// The admin settings form saves every non-numeric field as text, so a toggle
// arrives as the string "true"/"false" as often as a real boolean.
function flagOn(value) { return value === true || (typeof value === 'string' && value.trim().toLowerCase() === 'true'); }
function flagOff(value) { return value === false || (typeof value === 'string' && value.trim().toLowerCase() === 'false'); }
function paymentOptions(business = {}) {
  return {
    direct_vendor: !flagOff(business.directVendorPaymentEnabled),
    cash_on_delivery: flagOn(business.cashOnDeliveryEnabled),
    platform_collected: flagOn(business.platformCollectionEnabled),
  };
}
function vendorFee(feeRequired, amount) {
  if (feeRequired !== true) return {required: false, amount: 0};
  if (typeof amount !== 'number' || !Number.isFinite(amount) || amount < 0 || amount > 10000000) throw Error('Provide a valid vendor fee amount.');
  // A fee of ₹0 means there is nothing to pay: the vendor proceeds exactly as if the fee were off.
  if (amount === 0) return {required: false, amount: 0};
  return {required: true, amount: Math.round(amount * 100) / 100};
}
// Required vendor + shop details. Every field is mandatory; the account email
// comes from the verified auth token, never from the client.
function text(value, min, max, label) {
  const v = typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
  if (v.length < min || v.length > max) throw Error(`Provide ${label} (${min}-${max} characters).`);
  return v;
}
function vendorApplication(data = {}) {
  const phone = typeof data.phone === 'string' ? data.phone.trim() : '';
  if (!/^\+?[0-9][0-9 -]{6,17}$/.test(phone)) throw Error('Provide a valid contact phone number.');
  const pincode = typeof data.pincode === 'string' ? data.pincode.trim() : '';
  if (!/^\d{6}$/.test(pincode)) throw Error('Provide a valid six-digit pincode.');
  // The vendor's own device GPS, captured at registration time. This is informational for the admin
  // (shown on a map when reviewing) — it is never treated as an admin-verified location, so it never
  // substitutes for the separate verifyVendorShop check that gates purchase-code redemption.
  if (!validCoordinate(data.latitude) || !validCoordinate(data.longitude)) throw Error("Capture the shop's GPS location before submitting.");
  return {
    ownerName: text(data.ownerName, 2, 100, "the owner's full name"), phone,
    name: text(data.name, 2, 120, 'the shop name'), shopCategory: text(data.shopCategory, 2, 80, 'the shop category'),
    address: text(data.address, 5, 500, 'the shop address'), pincode, description: text(data.description, 10, 1000, 'a shop description'),
    latitude: data.latitude, longitude: data.longitude,
  };
}
// Field Assistant: a staff member's on-site shop details (only required when
// they're onboarding a shop that isn't in the system yet — an existing shop
// is referenced by id instead). Reuses vendorApplication()'s exact field
// rules (name/address/pincode/GPS) minus the vendor-specific owner/phone/
// description fields, which don't apply to a staff-captured shop.
function fieldShopDetails(data = {}) {
  const pincode = typeof data.pincode === 'string' ? data.pincode.trim() : '';
  if (!/^\d{6}$/.test(pincode)) throw Error('Provide a valid six-digit pincode.');
  // The GPS reading captured at the shop, same "never a substitute for
  // verifyVendorShop" caveat as vendorApplication()'s own GPS field.
  if (!validCoordinate(data.latitude) || !validCoordinate(data.longitude)) throw Error("Capture the shop's GPS location before submitting.");
  return {
    name: text(data.name, 2, 120, 'the shop name'),
    address: text(data.address, 5, 500, 'the shop address'),
    pincode,
    latitude: data.latitude,
    longitude: data.longitude,
  };
}
// Field Assistant: a staff member's own registration details (name/phone),
// required once, the first time they request access — reuses
// vendorApplication()'s exact phone-format rule.
function fieldStaffDetails(data = {}) {
  const phone = typeof data.phone === 'string' ? data.phone.trim() : '';
  if (!/^\+?[0-9][0-9 -]{6,17}$/.test(phone)) throw Error('Provide a valid contact phone number.');
  return {name: text(data.name, 2, 100, 'your full name'), phone};
}
// Field Assistant: the item a staff member captured (name/price/stock), reusing
// validateVendorChange's exact money/stock/name bounds.
function fieldItemDetails(data = {}) {
  const name = text(data.name, 2, 120, 'the item name');
  const price = data.price;
  if (typeof price !== 'number' || !Number.isFinite(price) || price < 0 || price > 10000000) throw Error('price must be a number from 0 to 10000000.');
  const stock = data.stock;
  if (!Number.isInteger(stock) || stock < 0 || stock > 1000000) throw Error('stock must be a whole number from 0 to 1000000.');
  return {name, price, stock};
}
const productChangeFields = {
  price: ['price', 'compareAtPrice', 'prices'],
  stock: ['stock'],
  product: ['name', 'description', 'categoryId', 'unit', 'imageUrl', 'images', 'tags'],
  shop: ['name', 'description', 'address', 'phone', 'whatsapp', 'imageUrl'],
  newProduct: ['name', 'description', 'categoryId', 'unit', 'imageUrl', 'price', 'stock', 'kind'],
};
// Validates the values a vendor proposes for a public change. Throws Error(message).
function validateVendorChange(type, changes) {
  const money = key => { const v = changes[key]; if (typeof v !== 'number' || !Number.isFinite(v) || v < 0 || v > 10000000) throw Error(`${key} must be a number from 0 to 10000000.`); };
  if (type === 'newProduct') {
    text(changes.name, 2, 120, 'the product name'); money('price');
    if (changes.kind !== undefined && !['product', 'service'].includes(changes.kind)) throw Error('Choose product or service.');
  }
  if (changes.price !== undefined) money('price');
  if (changes.compareAtPrice !== undefined) money('compareAtPrice');
  if (changes.stock !== undefined && (!Number.isInteger(changes.stock) || changes.stock < 0 || changes.stock > 1000000)) throw Error('stock must be a whole number from 0 to 1000000.');
  if (type === 'stock' && changes.stock === undefined) throw Error('Provide the stock quantity.');
  if (changes.name !== undefined) text(changes.name, 2, 120, 'the name');
  if (changes.description !== undefined && (typeof changes.description !== 'string' || changes.description.length > 2000)) throw Error('Description is too long.');
  if (changes.imageUrl !== undefined && changes.imageUrl !== '' && (typeof changes.imageUrl !== 'string' || !/^https?:\/\//.test(changes.imageUrl) || changes.imageUrl.length > 2000)) throw Error('Image must be an uploaded photo.');
  if (changes.prices !== undefined && (typeof changes.prices !== 'object' || changes.prices === null || Object.entries(changes.prices).some(([k, v]) => !/^\d{6}$/.test(k) || typeof v !== 'number' || !(v >= 0)))) throw Error('Location prices must be pincode=amount pairs.');
}
// An order only moves forward. A finished order (fulfilled or cancelled) is final: cancelling
// restores stock exactly once, so reopening one would leave its stock un-reserved.
const orderTransitions = {submitted: ['confirmed', 'cancelled'], confirmed: ['fulfilled', 'cancelled']};
function orderTransitionAllowed(from, to) { return (orderTransitions[from] || []).includes(to); }
module.exports = {hashPin, verifyPin, quote, distanceKm, validCoordinate, paymentOptions, vendorFee, flagOn, flagOff, orderTransitionAllowed, vendorApplication, validateVendorChange, productChangeFields, pointInRectangle, pointInPolygon, promotionMatchesLocation, fieldShopDetails, fieldItemDetails, fieldStaffDetails};
