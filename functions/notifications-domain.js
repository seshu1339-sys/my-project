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
// ---- Offer notifications
// The admin form saves toggles as text, so accept "true"/"false" as well as booleans.
const isOn = v => v === true || (typeof v === 'string' && v.trim().toLowerCase() === 'true');
const isOff = v => v === false || (typeof v === 'string' && v.trim().toLowerCase() === 'false');
// A promotion tells subscribers when it goes live unless the admin turned that off for it.
// The scrolling ticker is an announcement line, not an offer, so it only notifies when asked to.
function offerNotifiable(data, now = Date.now()) {
  if (!active(data, now) || isOff(data.notifySubscribers)) return false;
  return data.placement !== 'ticker' || isOn(data.notifySubscribers);
}
// One notification per promotion per go-live time; rescheduling the start notifies again.
const offerKey = (promotionId, data) => `offer:${promotionId}:${data.startsAt || 'initial'}`;
function offerCopy(data) {
  const body = [data.name || data.title, data.description].filter(v => typeof v === 'string' && v.trim()).join(' - ').slice(0, 180);
  return {title: 'New offer', body: body || 'A new offer is available. Open the shop to explore.'};
}
module.exports = {active, price, priceDrop, priceAlertKey, offerNotifiable, offerKey, offerCopy, INTEREST_WINDOW_MS, PRICE_ALERT_WINDOW_MS};
