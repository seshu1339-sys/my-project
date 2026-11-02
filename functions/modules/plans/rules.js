'use strict';
// The rules of a subscription plan, with no database in them.
//
// A plan never hides a shop. It only unlocks the special services listed in SERVICES, and only while it runs (functions/plan-gate.js).
const IST = 19800000;
const MAX_PRICE = 10000000;
const MAX_MONTHS = 120;

// The services a plan can unlock. The admin switches each one on separately (planServiceGates/main).
const SERVICES = ['vendorAds', 'rightBoxAds', 'exclusives'];

/// Checks a plan from the admin and returns the clean fields. Throws an Error with a plain message.
function validatePlan(data = {}) {
  const name = typeof data.name === 'string' ? data.name.trim().replace(/\s+/g, ' ') : '';
  if (name.length < 2 || name.length > 60) throw Error('Enter a plan name (2 to 60 characters).');
  const {price, durationMonths} = data;
  if (typeof price !== 'number' || !Number.isFinite(price) || price <= 0 || price > MAX_PRICE) throw Error('Enter a price above 0.');
  if (Math.abs(price * 100 - Math.round(price * 100)) > 1e-6) throw Error('A price can have at most 2 decimals.');
  if (!Number.isInteger(durationMonths) || durationMonths < 1 || durationMonths > MAX_MONTHS) throw Error(`Enter a duration of 1 to ${MAX_MONTHS} months.`);
  return {name, price, durationMonths, active: data.active !== false};
}

/// Only the known services, each true or false.
function validateGates(data = {}) {
  const gates = {};
  for (const service of SERVICES) {
    if (typeof data[service] === 'boolean') gates[service] = data[service];
  }
  if (!Object.keys(gates).length) throw Error('Choose a service to switch on or off.');
  return gates;
}

/// [ms] plus whole calendar months in India. The 31st becomes the last day of a shorter month.
function addMonths(ms, months) {
  const d = new Date(ms + IST);
  const day = d.getUTCDate();
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + months);
  const last = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  d.setUTCDate(Math.min(day, last));
  return d.getTime() - IST;
}

/// When a paid plan runs. The first plan starts on the payment date. A plan paid while another still runs starts when that one ends,
/// so no paid days are lost.
function planPeriod(paidAt, durationMonths, currentEndsAt = 0) {
  const startsAt = Math.max(paidAt, currentEndsAt);
  return {startsAt, endsAt: addMonths(startsAt, durationMonths)};
}

module.exports = {SERVICES, validatePlan, validateGates, addMonths, planPeriod, IST};
