'use strict';
// The rules of linking a vendor or a service provider to a staff member, with no database in them.
//
// Vendors and service providers register themselves (vendor app). A staff member who helped one register enters that person's ID in
// the staff app (Add > Vendor or Add > Services) within 30 minutes of the registration; then the person is linked to the staff member
// ("Registered by" in the admin panel). After 30 minutes the link is no longer possible and the person stays with the admin only.
// A link gives the staff member no access at all to the person's shop, items or prices: only a read-only view of their updates.
const LINK_WINDOW_MS = 30 * 60 * 1000;

/// The kind of account an ID belongs to: VEN-NRPM-116-325 is a vendor, SRV-NRPM-116-001 a service provider. Null when it is neither.
function parseCode(value) {
  const code = typeof value === 'string' ? value.trim().toUpperCase().replace(/\s+/g, '') : '';
  const match = code.match(/^(VEN|SRV)-[A-Z]{2,6}-\d{3}-\d{3}$/);
  if (!match) return null;
  return {kind: match[1] === 'VEN' ? 'vendor' : 'provider', code};
}

const minutesText = ms => {
  const minutes = Math.max(1, Math.ceil(ms / 60000));
  return `${minutes} minute${minutes === 1 ? '' : 's'}`;
};

/// Why this registration cannot be linked now, or null when it can.
function linkProblem(registeredAt, now) {
  if (!registeredAt) return 'This registration has no time yet. Try again in a moment.';
  if (now - registeredAt > LINK_WINDOW_MS) return 'More than 30 minutes have passed since this registration, so it cannot be linked. It stays with the LOCAMARKET team.';
  return null;
}

/// How long is left to link (for the staff app's message).
const timeLeftText = (registeredAt, now) => minutesText(registeredAt + LINK_WINDOW_MS - now);

const linkId = (kind, accountUid) => `${kind}_${accountUid}`;

function distanceKm(lat1, lon1, lat2, lon2) {
  const rad = d => (d * Math.PI) / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lon2 - lon1) / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);

/// Owner, 6 Nov 2026: a staff member links only vendors and providers whose registered place is inside their own area (its centre and
/// the town's radius). Returns why not, or null.
function areaProblem(area, place) {
  if (!area) return 'You need your own area first. Choose your area, then link the vendors in it.';
  const lat = num(place?.latitude), lng = num(place?.longitude);
  if (lat === null || lng === null) return 'This registration has no location, so it cannot be linked.';
  if (distanceKm(area.latitude, area.longitude, lat, lng) > area.radiusKm) return `This registration is outside your area "${area.name}", so you cannot link it.`;
  return null;
}

module.exports = {LINK_WINDOW_MS, parseCode, linkProblem, timeLeftText, linkId, areaProblem, distanceKm};
