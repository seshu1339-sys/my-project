'use strict';
// Quick Add Item: the pure rules (no Firebase), shared by quick-items.js and its tests.
// An item is submitted by a Staff or Vendor account, waits for the admin ('pending'), and once
// approved is shown to customers only between startsAt and expiresAt.

const QUICK_UNITS = ['per kg', 'per piece', 'per dozen', 'per litre', 'per bundle', 'per packet', 'per 500 g', 'per 250 g'];
const DURATION_UNITS = {hours: [1, 2, 3, 4], days: [1, 2, 3]};
const HOUR_MS = 3600 * 1000;
const DAY_MS = 24 * HOUR_MS;
const DEFAULT_DAILY_LIMIT = {staff: 15, vendor: 6};
const IST_OFFSET_MS = 330 * 60 * 1000;

const text = (value, min, max, label) => {
  const v = typeof value === 'string' ? value.trim() : '';
  if (v.length < min || v.length > max) throw Error(`Enter ${label} (${min}-${max} characters).`);
  return v;
};

/// The calendar day in India (IST) as 'YYYY-MM-DD'; the daily limit resets at midnight there.
const dayKey = (ms = Date.now()) => new Date(ms + IST_OFFSET_MS).toISOString().slice(0, 10);

const durationMs = (unit, value) => {
  if (!DURATION_UNITS[unit] || !DURATION_UNITS[unit].includes(value)) throw Error('Choose Hours (1-4) or Days (1-3).');
  return value * (unit === 'hours' ? HOUR_MS : DAY_MS);
};

/// The admin-configurable per-day limit for a role (settings/business), else the default.
function dailyLimit(role, business = {}) {
  const raw = Number(business[role === 'staff' ? 'quickItemsPerDayStaff' : 'quickItemsPerDayVendor']);
  return Number.isInteger(raw) && raw >= 1 && raw <= 1000 ? raw : DEFAULT_DAILY_LIMIT[role];
}

/// Validates what the phone sent. Returns the clean values; throws Error(message) otherwise.
/// [now] is only used for the "Now" start and for the schedule sanity check.
function quickItemDetails(data = {}, now = Date.now()) {
  const price = data.price;
  if (typeof price !== 'number' || !Number.isFinite(price) || price <= 0 || price > 1000000) throw Error('Rate must be a number above 0.');
  if (!QUICK_UNITS.includes(data.unit)) throw Error('Choose the unit, such as per kg or per piece.');
  const categoryId = data.categoryId;
  if (typeof categoryId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(categoryId)) throw Error('Choose a category.');
  const startMode = data.startMode === 'schedule' ? 'schedule' : data.startMode === 'now' ? 'now' : null;
  if (!startMode) throw Error('Choose Now or Schedule.');
  let requestedStartMs = now;
  if (startMode === 'schedule') {
    requestedStartMs = data.scheduleAt;
    if (!Number.isFinite(requestedStartMs)) throw Error('Pick the date and time to start.');
    if (requestedStartMs < now - 5 * 60 * 1000) throw Error('The scheduled start must be in the future.');
    if (requestedStartMs > now + 30 * DAY_MS) throw Error('Schedule at most 30 days ahead.');
  }
  return {
    name: text(data.name, 2, 80, 'the item name'),
    categoryId, price, unit: data.unit, startMode, requestedStartMs,
    durationUnit: data.durationUnit, durationValue: data.durationValue,
    durationMs: durationMs(data.durationUnit, data.durationValue),
  };
}

/// When an approved item starts and ends. The clock starts at the LATER of the admin's approval
/// and the start time the person asked for -- never at the moment it was saved.
function approvedWindow(approvedAtMs, requestedStartMs, durationMillis) {
  const startsAtMs = Math.max(approvedAtMs, requestedStartMs);
  return {startsAtMs, expiresAtMs: startsAtMs + durationMillis};
}

/// Where an item is in its life: pending | rejected | cancelled | scheduled | live | expired.
/// [item] has status plus startsAtMs/expiresAtMs (milliseconds) once approved.
function itemPhase(item, now = Date.now()) {
  if (item.status === 'approved') {
    if (now >= item.expiresAtMs) return 'expired';
    return now >= item.startsAtMs ? 'live' : 'scheduled';
  }
  return item.status; // pending | rejected | cancelled | expired (marked by the job)
}

module.exports = {QUICK_UNITS, DURATION_UNITS, DEFAULT_DAILY_LIMIT, dayKey, durationMs, dailyLimit, quickItemDetails, approvedWindow, itemPhase};
