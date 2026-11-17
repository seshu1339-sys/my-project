'use strict';
// The rules of a subscription plan, with no database in them.
//
// A plan never hides a shop. It only unlocks the special services listed in SERVICES, and only while it runs (functions/plan-gate.js).
const IST = 19800000;
const MAX_PRICE = 10000000;
const MAX_MONTHS = 120;
// How many items (each with its photos) a vendor may have: on the free plan unless the admin changes it (planServiceGates/main
// .freeItemLimit), and on a plan unless the admin sets the plan's own number (vendorPlans/<id>.itemLimit).
const DEFAULT_FREE_ITEM_LIMIT = 2;
const DEFAULT_PLAN_ITEM_LIMIT = 10;
const MAX_ITEM_LIMIT = 100;
// Paid plans come in three kinds (owner, 6 Nov 2026): Silver (small), Gold (middle), Premium (biggest). They differ only in how many
// extra photos the vendor may have and how far (km) the vendor's ad and offer reach users. Every paid plan has the same services.
// Platinum and Diamond were added on 13 Nov 2026; more kinds can be added here later (and in lib/modules/plans/plan_model.dart).
const TIERS = ['silver', 'gold', 'platinum', 'diamond', 'premium'];
const DEFAULT_EXTRA_PHOTOS = 10;
const MAX_EXTRA_PHOTOS = 30;
const DEFAULT_RADIUS_KM = 25;
const MAX_RADIUS_KM = 500;
const FREE_EXTRA_PHOTOS = 2;
// How many Today's Offers boxes a plan gives (owner, 7 Nov 2026): Silver 1, Gold 3, Premium as the admin sets (5 until then). The admin
// can set the number of every plan.
// Owner, 13 Nov 2026: Gold 2, Platinum 4, Diamond 6.
const DEFAULT_OFFER_BOXES = {silver: 1, gold: 2, platinum: 4, diamond: 6, premium: 5};
const MAX_OFFER_BOXES = 20;
const itemLimitOk = n => Number.isInteger(n) && n >= 0 && n <= MAX_ITEM_LIMIT;

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
  const itemLimit = data.itemLimit ?? DEFAULT_PLAN_ITEM_LIMIT;
  if (!itemLimitOk(itemLimit) || itemLimit < 1) throw Error(`Enter how many items the plan allows (1 to ${MAX_ITEM_LIMIT}).`);
  const tier = data.tier ?? 'premium';
  if (!TIERS.includes(tier)) throw Error('Choose Silver, Gold, Platinum, Diamond or Premium.');
  const extraPhotos = data.extraPhotos ?? DEFAULT_EXTRA_PHOTOS;
  if (!Number.isInteger(extraPhotos) || extraPhotos < 0 || extraPhotos > MAX_EXTRA_PHOTOS) throw Error(`Enter how many extra photos the plan allows (0 to ${MAX_EXTRA_PHOTOS}).`);
  const radiusKm = data.radiusKm ?? DEFAULT_RADIUS_KM;
  if (typeof radiusKm !== 'number' || !Number.isFinite(radiusKm) || radiusKm < 1 || radiusKm > MAX_RADIUS_KM) throw Error(`Enter how many km the ads and offers reach (1 to ${MAX_RADIUS_KM}).`);
  const offerBoxes = data.offerBoxes ?? DEFAULT_OFFER_BOXES[tier];
  if (!Number.isInteger(offerBoxes) || offerBoxes < 0 || offerBoxes > MAX_OFFER_BOXES) throw Error(`Enter how many Today's Offers boxes the plan gives (0 to ${MAX_OFFER_BOXES}).`);
  return {name, tier, price, durationMonths, itemLimit, extraPhotos, radiusKm: Math.round(radiusKm * 10) / 10, offerBoxes, active: data.active !== false};
}

/// Only the known services, each true or false, and the free plan's item limit.
function validateGates(data = {}) {
  const gates = {};
  for (const service of SERVICES) {
    if (typeof data[service] === 'boolean') gates[service] = data[service];
  }
  if (data.freeExtraPhotos !== undefined) {
    if (!Number.isInteger(data.freeExtraPhotos) || data.freeExtraPhotos < 0 || data.freeExtraPhotos > MAX_EXTRA_PHOTOS) throw Error(`Enter how many extra photos a free vendor may have (0 to ${MAX_EXTRA_PHOTOS}).`);
    gates.freeExtraPhotos = data.freeExtraPhotos;
  }
  if (data.freeItemLimit !== undefined) {
    if (!itemLimitOk(data.freeItemLimit)) throw Error(`Enter how many items a free vendor may have (0 to ${MAX_ITEM_LIMIT}).`);
    gates.freeItemLimit = data.freeItemLimit;
  }
  if (!Object.keys(gates).length) throw Error('Choose a service to switch on or off.');
  return gates;
}

/// The items a plan allows: the number saved on it, or the default for plans made before plans had one.
const planItemLimit = plan => (itemLimitOk(plan?.itemLimit) && plan.itemLimit >= 1 ? plan.itemLimit : DEFAULT_PLAN_ITEM_LIMIT);
/// What a plan gives besides the shared services: its kind, extra photos, km and Today's Offers boxes (defaults for plans made before
/// these existed).
const planBenefits = plan => {
  const tier = TIERS.includes(plan?.tier) ? plan.tier : 'premium';
  return {
    tier,
    extraPhotos: Number.isInteger(plan?.extraPhotos) && plan.extraPhotos >= 0 ? plan.extraPhotos : DEFAULT_EXTRA_PHOTOS,
    radiusKm: typeof plan?.radiusKm === 'number' && plan.radiusKm >= 1 ? plan.radiusKm : DEFAULT_RADIUS_KM,
    offerBoxes: Number.isInteger(plan?.offerBoxes) && plan.offerBoxes >= 0 && plan.offerBoxes <= MAX_OFFER_BOXES ? plan.offerBoxes : DEFAULT_OFFER_BOXES[tier],
  };
};

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

module.exports = {TIERS, DEFAULT_OFFER_BOXES, MAX_OFFER_BOXES, FREE_EXTRA_PHOTOS, DEFAULT_EXTRA_PHOTOS, DEFAULT_RADIUS_KM, planBenefits, SERVICES, validatePlan, validateGates, addMonths, planPeriod, planItemLimit, IST, DEFAULT_FREE_ITEM_LIMIT, DEFAULT_PLAN_ITEM_LIMIT, MAX_ITEM_LIMIT};
