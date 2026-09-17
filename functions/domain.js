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
module.exports = {hashPin, verifyPin, quote};
