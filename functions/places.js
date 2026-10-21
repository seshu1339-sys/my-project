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


// ---- coordinates ---------------------------------------------------------------------------
// About a quarter of the directory's rows have no coordinates (stored as 0, 0). So the nearest place to a
// GPS fix can still be found everywhere, each such row gets an estimate from its neighbours: the other
// offices with the same pincode, else the same first 5 digits, else 4, else the district's average.
// lib/domain/places.dart does exactly the same, and a test keeps the two identical.
const has = (lat, lng) => !(lat === 0 && lng === 0);
const round3 = value => Math.round(value * 1000) / 1000;

/// [[lat, lng], ...] for every row of data.places, with the missing ones estimated.
function filledCoordinates(places) {
  const sums = new Map();
  const keysOf = row => {
    const pin = String(row[2]);
    return ['p' + pin, 'a' + pin.slice(0, 5), 'b' + pin.slice(0, 4), 'd' + row[1]];
  };
  for (const row of places) {
    if (!has(row[4], row[5])) continue;
    for (const key of keysOf(row)) {
      const have = sums.get(key) || [0, 0, 0];
      have[0] += row[4]; have[1] += row[5]; have[2] += 1;
      sums.set(key, have);
    }
  }
  return places.map(row => {
    if (has(row[4], row[5])) return [row[4], row[5]];
    for (const key of keysOf(row)) {
      const found = sums.get(key);
      if (found) return [round3(found[0] / found[2]), round3(found[1] / found[2])];
    }
    return [0, 0];
  });
}

let directory = null;
function load() {
  if (directory) return directory;
  const data = require('./data/places.v1.json');
  const coordinates = filledCoordinates(data.places);
  directory = data.places.map((row, i) => {
    const [districtName, stateIndex] = data.districts[row[1]];
    return {
      name: row[0], district: districtName, state: data.states[stateIndex], pincode: String(row[2]),
      village: row[3] === 1, head: row[3] === 2, latitude: coordinates[i][0], longitude: coordinates[i][1],
      town: row.length > 6 ? row[6] : row[0],
    };
  });
  return directory;
}

const radians = Math.PI / 180;
function kmBetween(aLat, aLng, bLat, bLng) {
  const dLat = (bLat - aLat) * radians, dLng = (bLng - aLng) * radians;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(aLat * radians) * Math.cos(bLat * radians) * Math.sin(dLng / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(h));
}

/// The town nearest to a GPS fix (the same rule as PlacesIndex.nearestTown in the app), or null when
/// the nearest place is more than [maxKm] away, i.e. the phone is not in Andhra Pradesh / Telangana.
function nearestPlace(latitude, longitude, maxKm = 60) {
  let bestTown = null, bestAny = null, townKm = Infinity, anyKm = Infinity;
  for (const place of load()) {
    if (!has(place.latitude, place.longitude)) continue;
    const km = kmBetween(latitude, longitude, place.latitude, place.longitude) - (place.head ? 3 : 0);
    if (km < anyKm) { anyKm = km; bestAny = place; }
    if (!place.village && km < townKm) { townKm = km; bestTown = place; }
  }
  const best = bestTown && townKm <= anyKm + 5 ? bestTown : bestAny;
  const distance = best === bestTown ? townKm : anyKm;
  return best && distance <= maxKm ? best : null;
}

/// The directory row for a town the app offered: its town name, district and a pincode of it.
function findPlace({town, district, pincode}) {
  const wanted = value => String(value || '').trim().toLowerCase().replace(/s+/g, ' ');
  return load().find(place => place.pincode === String(pincode || '').trim() && wanted(place.town) === wanted(town) && wanted(place.district) === wanted(district)) || null;
}

module.exports = {placeForPincode, locationStamp, filledCoordinates, nearestPlace, findPlace, kmBetween};
