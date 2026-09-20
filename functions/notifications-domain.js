'use strict';
const INTEREST_WINDOW_MS = 90 * 86400000;      // how long a product view keeps a customer "interested"
const PRICE_ALERT_WINDOW_MS = 7 * 86400000;    // the same alert (same price) is not repeated within this window
function active(data, now = Date.now()) {
  const start = data.startsAt ? Date.parse(data.startsAt) : -Infinity;
  const end = data.endsAt ? Date.parse(data.endsAt) : Infinity;
  return data.active !== false && start <= now && now < end;
}
function price(data, pincode) {
  const value = data.prices?.[pincode] ?? data.price;
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
}
function priceDrop(before, after, pincode, now = Date.now()) {
  const oldPrice = price(before, pincode), newPrice = price(after, pincode);
  return active(after, now) && oldPrice !== null && newPrice !== null && newPrice < oldPrice ? newPrice : null;
}
// One alert per customer, product, pincode and price.
function priceAlertKey(productId, pincode, value) {
  return `priceDrop:${productId}:${pincode || 'any'}:${value}`;
}
module.exports = {active, price, priceDrop, priceAlertKey, INTEREST_WINDOW_MS, PRICE_ALERT_WINDOW_MS};
