'use strict';
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
module.exports = {active, priceDrop};
