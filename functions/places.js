'use strict';
// Which town / district / state a pincode belongs to, from the same India Post
// directory the apps use (functions/data/places.v1.json is a copy of
// web/data/places.v1.json; a test keeps the two identical). Used to aim offer
// push notifications at the places an offer was made for. Loaded on first use only.
let byPincode = null;

function build() {
  const data = require('./data/places.v1.json');
  const map = new Map();
  for (const row of data.places) {
    const [name, districtIndex, pin, kind] = row;
    const [districtName, stateIndex] = data.districts[districtIndex];
    const candidate = {town: row.length > 6 ? row[6] : name, district: districtName, state: data.states[stateIndex], rank: kind === 2 ? 0 : kind === 0 ? 1 : 2};
    const key = String(pin);
    const have = map.get(key);
    // head office first, then the first town-type office, then any office (as the app does)
    if (!have || candidate.rank < have.rank) map.set(key, candidate);
  }
  return map;
}

/// {town, district, state} for a pincode, or {} when it is not in Andhra Pradesh / Telangana.
function placeForPincode(pincode) {
  if (!byPincode) byPincode = build();
  const found = byPincode.get(String(pincode || '').trim());
  return found ? {town: found.town, district: found.district, state: found.state} : {};
}

/// The place details an approved product or shop carries so the site can show (and later filter by)
/// where it is: the shop's pincode and GPS plus the town/district/state found from the pincode.
function locationStamp(shop = {}) {
  const out = {};
  const pincode = String(shop.pincode || '').trim();
  if (pincode) Object.assign(out, {pincode}, placeForPincode(pincode));
  for (const key of ['latitude', 'longitude']) if (Number.isFinite(shop[key])) out[key] = shop[key];
  return out;
}

module.exports = {placeForPincode, locationStamp};
