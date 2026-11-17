'use strict';
// The staff chat: their area, the daily target, missed days, adding Today's Offers, the Terms & Conditions and their account. It never
// reads tickets. Each fact is read with the staff member's uid from the server (the Staff Area System's own records, read here only),
// and only what the chosen category needs.
const {dateText} = require('../rules');

const DEFAULTS = {monthlyPhotoTarget: 100, monthlyVendorTarget: 10, monthlyPaidVendorTarget: 2, rateDaysPerWeek: 4, maxMissedDays: 7};
// The same default Terms as functions/modules/staff-areas/rules.js (modules never import each other), until the admin writes their own.
const DEFAULT_TERMS = [
  '1. There is no fixed salary. You earn a commission based on your work.',
  '2. One area per staff member. You work only in the area you registered.',
  "3. You add only Today's Offers for the shops in your area. You never change a vendor's profile, photos, items or normal prices.",
  '4. You update the rates of the shops in your area on the minimum number of days every week, each with a live camera photo taken at the shop (within 100 metres, with real GPS). Photos sent from anywhere else never count.',
  '5. You complete the monthly targets: photos, vendor registrations and paid vendor registrations. A month counts only when its target is complete.',
  '6. Days without rate updates beyond the weekly allowance are missed days. When the allowed number of missed days is reached, your staff ID is deactivated automatically and your area is given to another person. You are warned one day before.',
  '7. LOCAMARKET can change these rules at any time.',
].join('\n');
const istDay = ms => new Date(ms + 19800000).toISOString().slice(0, 10);

async function settings(db) {
  const s = (await db.collection('staffAreaSettings').doc('main').get()).data() ?? {};
  const n = key => (Number.isInteger(s[key]) ? s[key] : DEFAULTS[key]);
  return {
    monthlyTargets: {livePhotos: n('monthlyPhotoTarget'), vendorRegistrations: n('monthlyVendorTarget'), paidVendorRegistrations: n('monthlyPaidVendorTarget'), countsOnlyWhenComplete: true},
    rateUpdateDaysAWeek: n('rateDaysPerWeek'),
    missedDaysThatStopTheAccount: n('maxMissedDays'),
    terms: s.terms || DEFAULT_TERMS,
  };
}

async function areaFacts(db, uid, now) {
  const [mineDoc, rules] = await Promise.all([db.collection('staffAreaStaff').doc(uid).get(), settings(db)]);
  const mine = mineDoc.data() ?? {};
  const area = mine.areaId ? (await db.collection('staffAreas').doc(mine.areaId).get()).data() : null;
  const month = istDay(now).slice(0, 7);
  const days = await db.collection('staffAreaDays').where('staffUid', '==', uid).where('month', '==', month).get();
  const counted = days.docs.map(d => d.data());
  return {
    myArea: area ? {name: area.name, town: area.town, radiusKm: area.radiusKm, status: area.status === 'pending' ? 'held for you until the admin approves you' : area.status} : 'no area yet: choose a free (green) area on the map while standing inside it',
    monthlyTargets: rules.monthlyTargets,
    rateUpdateDaysAWeek: rules.rateUpdateDaysAWeek,
    missedDaysThisMonth: mine.month === month ? mine.missedThisMonth || 0 : 0,
    missedDaysThatStopTheAccount: rules.missedDaysThatStopTheAccount,
    freeDaysOffUsedThisWeek: mine.offDaysThisWeek || 0,
    warning: mine.month === month ? mine.warning || '' : '',
    deactivated: mine.deactivatedAt ? {on: dateText(mine.deactivatedAt), reason: mine.deactivatedReason || ''} : 'no',
    daysThisMonth: counted.map(d => ({day: d.day, rateUpdates: d.rateUpdates ?? 0, result: d.outcome ?? ''})).sort((a, b) => a.day.localeCompare(b.day)),
    todayNote: 'Today\'s rate updates and the monthly progress are on your dashboard (Refresh).',
    photoRule: 'Only a live camera photo taken at the shop (within 100 m, real GPS, no fake GPS app) counts.',
  };
}

async function offerFacts(db, uid, now) {
  const since = now - 7 * 86400000;
  // One equality only (no extra index); the last 7 days are picked here.
  const mine = await db.collection('vendorOffers').where('staffUid', '==', uid).get();
  return {
    myOffersLast7Days: mine.docs.map(d => d.data()).filter(o => (o.createdAt?.toMillis?.() ?? 0) >= since).map(o => ({shop: o.shopName, item: o.title, offerPrice: o.offerPrice, normalPrice: o.regularPrice, validOn: o.validDate, status: o.status})),
    rules: "Only Today's Offers (rate updates), only for shops inside your area, each with a live camera photo taken within 100 m of the shop with real GPS; the item comes from the admin's list; the offer price must be lower than the normal price; it ends by itself after its date.",
  };
}

async function accountFacts(db, uid) {
  const [staff, links] = await Promise.all([db.collection('fieldStaff').doc(uid).get(), db.collection('staffLinks').where('staffUid', '==', uid).get()]);
  const s = staff.data() ?? {};
  return {
    status: s.status, staffCode: s.staffCode ?? '', name: s.name ?? '',
    vendorsLinked: links.docs.filter(d => d.data().kind === 'vendor').length, providersLinked: links.docs.filter(d => d.data().kind === 'provider').length,
    linking: 'Vendors register themselves; enter their Vendor ID under Add within 30 minutes of their registration. You cannot change their shop, items or prices.',
  };
}

module.exports = {
  kind: 'staff',
  collection: 'flashStaffChats',
  categories: ['My area', 'Targets', 'Missed days', 'Adding offers', 'Terms', 'Account', 'App', 'Other'],
  helpField: 'helpStaff',
  rules: 'You are talking with a field staff member. Help with their area, their monthly targets and weekly rate days, their missed days, adding Today\'s Offers, the Terms & Conditions, linking vendors and their account. Quote the Terms only from FACTS. A pay or commission question, an area dispute, a deactivated account or anything else needs the team.',

  /// Only someone with a staff record, whatever its status: a suspended member can still ask for help.
  allowed: async (db, uid) => (await db.collection('fieldStaff').doc(uid).get()).exists,
  label: async (db, uid) => {
    const staff = (await db.collection('fieldStaff').doc(uid).get()).data();
    return [staff?.name, staff?.staffCode].filter(Boolean).join(' · ');
  },
  facts: async (db, uid, category, now = Date.now()) => {
    if (['My area', 'Targets', 'Daily target', 'Missed days', 'Work'].includes(category)) return areaFacts(db, uid, now);
    if (category === 'Adding offers') return offerFacts(db, uid, now);
    if (category === 'Terms') return settings(db);
    if (category === 'Account') return accountFacts(db, uid);
    return {};
  },
};
