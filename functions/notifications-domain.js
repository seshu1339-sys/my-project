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
// ---- "You moved to a new place": the live offers made specifically for that place.
const {promotionMatchesLocation, promotionMatchesPlace, parseLocationList} = require('./domain');
const LOCATION_OFFER_PLACEMENTS = ['carousel', 'ad', 'box'];
const placeLabel = place => String(place.town || '').trim();
/// Live offers/ads aimed at specific places that include [place] (never general offers and never
/// another place's), best first: by their display order, then id. [promotions] is [{id, data}].
function locationOffers(promotions, place, subscriber = {}, now = Date.now()) {
  return promotions
    .filter(({data}) => active(data, now) && LOCATION_OFFER_PLACEMENTS.includes(data.placement) && !isOff(data.notifySubscribers)
      && parseLocationList(data.locations).length > 0 && promotionMatchesPlace(data, place)
      && promotionMatchesLocation(data, {customerPincode: subscriber.pincode, customerLatitude: subscriber.latitude, customerLongitude: subscriber.longitude}))
    .sort((a, b) => (Number(a.data.order) || 0) - (Number(b.data.order) || 0) || String(a.id).localeCompare(String(b.id)));
}
// One notice per place and set of offers: the same place with the same offers is never announced twice.
const locationNoticeKey = (place, offers) => `location:${placeLabel(place).toLowerCase()}|${String(place.district || '').toLowerCase()}:${offers.map(o => `${o.id}@${o.data.startsAt || ''}`).join(',')}`;
function locationNoticeCopy(place, offers) {
  const names = offers.map(o => String(o.data.name || o.data.title || '').trim()).filter(Boolean);
  const shown = names.slice(0, 3).join(' • ');
  const more = names.length > 3 ? ` +${names.length - 3} more` : '';
  return {title: `Offers in ${placeLabel(place)}`, body: (shown ? shown + more : 'New offers are available near you. Open the shop to explore.').slice(0, 180)};
}
// ---- "Offers near you" by distance (owner, 11 Nov 2026: offers reach customers only within the admin's one km of their shop; the
// same rule as the website and the apps, lib/domain/reach.dart). The town rule above stays for reference.
const {distanceKm} = require('./radius');
const DEFAULT_REACH_KM = 10;
/// The admin's km (settings/business.radiusKm), 0.5 to 500, 10 when not set.
function reachKmOf(business = {}) {
  const km = Number(business.radiusKm);
  return Number.isFinite(km) && km > 0 ? Math.min(500, Math.max(0.5, km)) : DEFAULT_REACH_KM;
}
/// The shop an offer belongs to: shopId, radiusShopId, a "shop" tap, or a "shop:ID" target. '' when it has none.
function linkedShopId(item = {}) {
  for (const key of ['shopId', 'radiusShopId']) if (typeof item[key] === 'string' && item[key].trim()) return item[key].trim();
  if (item.tapAction === 'shop' && typeof item.tapValue === 'string' && item.tapValue.trim()) return item.tapValue.trim();
  const target = String(item.target || '');
  return target.startsWith('shop:') ? target.slice(5).trim() : '';
}
const millisOf = value => (typeof value?.toMillis === 'function' ? value.toMillis() : Date.parse(String(value ?? '')));
/// The live offers within [km] of the point: the admin's promotions (carousel, ads, boxes) and the vendors' live offers, each by its
/// shop's place. An offer without a shop, or a shop without a place, reaches nobody.
function nearbyOffers({promotions = [], vendorOffers = [], shops = new Map(), latitude, longitude, km = DEFAULT_REACH_KM, now = Date.now()}) {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || (latitude === 0 && longitude === 0)) return [];
  const near = item => {
    const shop = shops.get(linkedShopId(item));
    const lat = Number(shop?.latitude), lng = Number(shop?.longitude);
    return Number.isFinite(lat) && Number.isFinite(lng) && !(lat === 0 && lng === 0) && distanceKm(latitude, longitude, lat, lng) <= km;
  };
  const admin = promotions.filter(({data}) => active(data, now) && LOCATION_OFFER_PLACEMENTS.includes(data.placement) && !isOff(data.notifySubscribers) && near(data));
  const vendor = vendorOffers.filter(({data}) => data.status === 'live' && millisOf(data.endsAt) > now && near(data))
    .map(({id, data}) => ({id: `vo:${id}`, data: {...data, name: data.title || data.name, startsAt: data.postedAt ?? data.createdAt}}));
  return [...admin, ...vendor].sort((a, b) => (Number(a.data.order) || 0) - (Number(b.data.order) || 0) || String(a.id).localeCompare(String(b.id)));
}
/// One notice per area (about 1 km squares) and set of offers.
const nearbyNoticeKey = (latitude, longitude, offers) =>
  `nearby:${latitude.toFixed(2)},${longitude.toFixed(2)}:${offers.map(o => `${o.id}@${String(millisOf(o.data.startsAt) || '')}`).join(',')}`;
function nearbyNoticeCopy(offers, area = '') {
  const names = offers.map(o => String(o.data.name || o.data.title || '').trim()).filter(Boolean);
  const shown = names.slice(0, 3).join(' • ');
  const more = names.length > 3 ? ` +${names.length - 3} more` : '';
  return {title: area ? `Offers near ${area}` : 'Offers near you', body: (shown ? shown + more : 'New offers are available near you. Open the shop to explore.').slice(0, 180)};
}
module.exports = {nearbyOffers, nearbyNoticeKey, nearbyNoticeCopy, reachKmOf, linkedShopId, locationOffers, locationNoticeKey, locationNoticeCopy, active, price, priceDrop, priceAlertKey, offerNotifiable, offerKey, offerCopy, INTEREST_WINDOW_MS, PRICE_ALERT_WINDOW_MS};
