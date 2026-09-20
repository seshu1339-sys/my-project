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
  if (typeof amount !== 'number' || !Number.isFinite(amount) || amount <= 0 || amount > 10000000) throw Error('Provide a valid vendor fee amount.');
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
  return {
    ownerName: text(data.ownerName, 2, 100, "the owner's full name"), phone,
    name: text(data.name, 2, 120, 'the shop name'), shopCategory: text(data.shopCategory, 2, 80, 'the shop category'),
    address: text(data.address, 5, 500, 'the shop address'), pincode, description: text(data.description, 10, 1000, 'a shop description'),
  };
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
module.exports = {hashPin, verifyPin, quote, distanceKm, validCoordinate, paymentOptions, vendorFee, flagOn, vendorApplication, validateVendorChange, productChangeFields};
