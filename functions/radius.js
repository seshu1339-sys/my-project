'use strict';
// The common radius for Ads and Today's Offers on the server: the same rule as lib/domain/radius.dart.
//   radiusKm (5 / 10 / 25 / 50 / 100), radiusShopId, radiusLat / radiusLng (the centre, copied from the shop).
// An ad / offer with a radius reaches only a customer inside the circle; one without a radius is not affected.
const OPTIONS = [5, 10, 25, 50, 100];
const num = value => { const n = Number(value); return Number.isFinite(n) ? n : 0; };

function distanceKm(lat1, lon1, lat2, lon2) {
  const rad = v => v * Math.PI / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lon2 - lon1) / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - Math.min(1, Math.max(0, a))));
}
const hasRadius = item => num(item?.radiusKm) > 0;
const centre = item => (num(item?.radiusLat) === 0 && num(item?.radiusLng) === 0 ? null : {lat: num(item.radiusLat), lng: num(item.radiusLng)});

/// A radius asked for in between goes to the next bigger option; null when it is bigger than the biggest.
function nextRadiusOption(km) { return OPTIONS.find(option => km <= option) ?? null; }

function radiusCovers(item, lat, lng) {
  if (!hasRadius(item)) return true;
  const c = centre(item);
  if (!c || typeof lat !== 'number' || typeof lng !== 'number') return false;
  return distanceKm(lat, lng, c.lat, c.lng) <= num(item.radiusKm);
}

const dateOf = value => { const t = Date.parse(value); return Number.isNaN(t) ? null : t; };
function runsTogether(a, b) {
  const aStart = dateOf(a.startsAt), aEnd = dateOf(a.endsAt), bStart = dateOf(b.startsAt), bEnd = dateOf(b.endsAt);
  return (aStart === null || bEnd === null || aStart < bEnd) && (bStart === null || aEnd === null || bStart < aEnd);
}

function samples(lat, lng, radiusKm) {
  const points = [[lat, lng]];
  const cosLat = Math.max(0.2, Math.cos(lat * Math.PI / 180));
  for (const ring of [0.5, 0.9]) {
    for (let i = 0; i < 8; i++) {
      const angle = i * Math.PI / 4;
      points.push([lat + radiusKm * ring * Math.sin(angle) / 111, lng + radiusKm * ring * Math.cos(angle) / (111 * cosLat)]);
    }
  }
  return points;
}

/// [others] = [{id, ...fields}]. How many other ads / offers with a radius, running at the same time, cover the busiest spot of the candidate's circle.
function areaLoad(candidate, others) {
  const c = centre(candidate);
  if (!hasRadius(candidate) || !c) return 0;
  const rivals = others.filter(o => o.id !== candidate.id && o.active !== false && (o.status ?? 'approved') === 'approved' && hasRadius(o) && centre(o) && runsTogether(candidate, o));
  let busiest = 0;
  for (const [lat, lng] of samples(c.lat, c.lng, num(candidate.radiusKm))) {
    busiest = Math.max(busiest, rivals.filter(o => radiusCovers(o, lat, lng)).length);
  }
  return busiest;
}

function areaFullMessage(candidate, others, max) {
  if (!(max > 0) || !hasRadius(candidate)) return null;
  const load = areaLoad(candidate, others);
  if (load + 1 <= max) return null;
  return `This area already has ${load} ads or offers running at the same time (the limit is ${max}). Choose a smaller radius, other dates, or raise the limit in the Ads settings.`;
}

module.exports = {OPTIONS, nextRadiusOption, hasRadius, radiusCovers, runsTogether, areaLoad, areaFullMessage, distanceKm};
