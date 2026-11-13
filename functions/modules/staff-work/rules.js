'use strict';
// The rules of staff work and pay, with no database in them (owner, 13 Nov 2026). Mirrored in lib/domain/staff_pay.dart.
//
// An UPDATE is a new item, a price change or a new offer of a vendor or service provider. The same item counts once a day however
// often its price changes. Only the updates of vendors and providers LINKED to a staff member count for that staff member; the ones
// of people linked to nobody count for nobody (they still show in their own ID report).
// Targets: a daily target (50 updates unless the admin changes it) and a monthly target (the daily one times the days of the month
// unless the admin sets one). Each staff member may have their own numbers; otherwise everyone has the same.
// Pay slabs: the admin's list of {percent, amount}. The month's pay is the amount of the highest slab reached (percent of the monthly
// target done). The app only works the amount out; the admin pays by hand and marks it paid.
const IST_MS = 5.5 * 60 * 60 * 1000;
const DEFAULT_DAILY_TARGET = 50;
const MAX_SLABS = 20;

const dayKey = now => new Date(now + IST_MS).toISOString().slice(0, 10);
const monthKey = now => dayKey(now).slice(0, 7);
function daysInMonth(month) {
  const [y, m] = String(month).split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

const millisOf = v => (typeof v?.toMillis === 'function' ? v.toMillis() : v ? Date.parse(String(v)) : NaN);

/// The update a product or service write is (a new item or a new price), or null. {owner, key, type}.
function updateOfItem(id, before, after) {
  if (!after || typeof after.ownerId !== 'string' || !after.ownerId) return null;
  if (!before) return {owner: after.ownerId, key: `item:${id}`, type: 'items'};
  if (typeof after.price === 'number' && after.price !== before.price) return {owner: after.ownerId, key: `item:${id}`, type: 'prices'};
  return null;
}

/// The update a vendor offer write is (a new offer, or one run again), or null.
function updateOfOffer(id, before, after, postedField = 'postedAt') {
  if (!after || typeof after.vendorId !== 'string' || !after.vendorId) return null;
  if (after.status && !['live', 'pending'].includes(after.status)) return null;
  const fresh = !before || millisOf(before[postedField]) !== millisOf(after[postedField]);
  return fresh ? {owner: after.vendorId, key: `offer:${id}`, type: 'offers'} : null;
}

const num = (v, min, max) => {
  const n = Number(v);
  return Number.isFinite(n) && n >= min && n <= max ? n : null;
};

/// The admin's slabs, checked and sorted by percent.
function cleanSlabs(list) {
  if (list === null || list === undefined) return null;
  if (!Array.isArray(list) || list.length > MAX_SLABS) throw Error(`Give at most ${MAX_SLABS} slabs.`);
  const slabs = list.map(s => ({percent: num(s?.percent, 1, 1000), amount: num(s?.amount, 0, 10000000)}));
  if (slabs.some(s => s.percent === null || s.amount === null)) throw Error('Each slab needs a percent (1 to 1000) and an amount (0 or more).');
  slabs.sort((a, b) => a.percent - b.percent);
  if (new Set(slabs.map(s => s.percent)).size !== slabs.length) throw Error('Two slabs have the same percent.');
  return slabs;
}

/// The targets and slabs of one staff member for a month: their own numbers where set, else everyone's.
function targetsFor(config = {}, own = {}, month) {
  const daily = num(own.dailyTarget, 1, 100000) ?? num(config.dailyTarget, 1, 100000) ?? DEFAULT_DAILY_TARGET;
  const monthly = num(own.monthlyTarget, 1, 10000000) ?? num(config.monthlyTarget, 1, 10000000) ?? daily * daysInMonth(month);
  const slabs = Array.isArray(own.slabs) ? own.slabs : Array.isArray(config.slabs) ? config.slabs : [];
  return {daily, monthly, slabs, ownNumbers: own.dailyTarget != null || own.monthlyTarget != null || Array.isArray(own.slabs)};
}

/// What a month's updates earn: the percent of the monthly target, the highest slab reached, its amount, and the next slab.
function payFor(updates, targets) {
  const percent = targets.monthly > 0 ? Math.round((updates / targets.monthly) * 1000) / 10 : 0;
  const reached = [...targets.slabs].filter(s => s.percent <= percent).pop() || null;
  const next = targets.slabs.find(s => s.percent > percent) || null;
  return {updates, percent, slab: reached, amount: reached ? reached.amount : 0, next};
}

module.exports = {IST_MS, DEFAULT_DAILY_TARGET, MAX_SLABS, dayKey, monthKey, daysInMonth, updateOfItem, updateOfOffer, cleanSlabs, targetsFor, payFor};
