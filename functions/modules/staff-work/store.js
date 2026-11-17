'use strict';
// Staff work: what this module reads and writes.
//   vendorActivity/<uid>/days/<YYYY-MM-DD>   {day, updates, items, prices, offers, keys: {<key>: true}}   every vendor / provider
//   vendorActivity/<uid>/months/<YYYY-MM>    {month, updates, items, prices, offers}
//   staffWork/<staffUid>/days/<day>          {day, updates, items, prices, offers, vendors: {<uid>: n}, keys}  linked people only
//   staffWork/<staffUid>/months/<month>      {month, updates, items, prices, offers, vendors: {<uid>: n}}
//   staffPayConfig/main                      {dailyTarget, monthlyTarget, slabs: [{percent, amount}]}   the admin's numbers for all
//   staffPayTargets/<staffUid>               {dailyTarget, monthlyTarget, slabs}                        one staff member's own numbers
//   staffPayouts/<staffUid>_<month>          {staffUid, staffCode, month, updates, target, percent, amount, method, status, paidAt,...}
// Reads staffLinks (who is linked to whom), fieldStaff, staffAreaStaff / staffAreas (the area), and for the ID report the person's
// registration, items, changes, offers, ads, ratings and reports. Read-only reports never change anything.
const {FieldValue, Timestamp, FieldPath} = require('firebase-admin/firestore');
const R = require('./rules');

const ID = /^[A-Za-z0-9_-]{1,128}$/;
const iso = v => (v?.toDate ? v.toDate().toISOString() : v instanceof Date ? v.toISOString() : v ?? null);

/// The staff member a vendor or provider is linked to, or null.
async function linkedStaff(db, owner) {
  for (const kind of ['vendor', 'provider']) {
    const link = (await db.collection('staffLinks').doc(`${kind}_${owner}`).get()).data();
    if (link?.staffUid) return link.staffUid;
  }
  return null;
}

/// Counts one update (once per key per day) for the person, and for their staff member when they are linked. Returns true if new.
async function recordUpdate(db, update, now = Date.now()) {
  if (!update || !ID.test(update.owner)) return false;
  const day = R.dayKey(now), month = R.monthKey(now);
  const staffUid = await linkedStaff(db, update.owner);
  const inc = FieldValue.increment(1);
  const vDay = db.collection('vendorActivity').doc(update.owner).collection('days').doc(day);
  const vMonth = db.collection('vendorActivity').doc(update.owner).collection('months').doc(month);
  return db.runTransaction(async tx => {
    const seen = (await tx.get(vDay)).data()?.keys?.[update.key];
    if (seen) return false;
    const counts = {updates: inc, [update.type]: inc};
    tx.set(vDay, {day, ...counts, keys: {[update.key]: true}, updatedAt: Timestamp.fromMillis(now)}, {merge: true});
    tx.set(vMonth, {month, ...counts}, {merge: true});
    tx.set(db.collection('vendorActivity').doc(update.owner), {uid: update.owner, lastUpdateAt: Timestamp.fromMillis(now)}, {merge: true});
    if (staffUid) {
      const sDay = db.collection('staffWork').doc(staffUid).collection('days').doc(day);
      const sMonth = db.collection('staffWork').doc(staffUid).collection('months').doc(month);
      tx.set(sDay, {day, ...counts, vendors: {[update.owner]: inc}, updatedAt: Timestamp.fromMillis(now)}, {merge: true});
      tx.set(sMonth, {month, ...counts, vendors: {[update.owner]: inc}}, {merge: true});
    }
    return true;
  });
}

async function payConfig(db) {
  return (await db.collection('staffPayConfig').doc('main').get()).data() || {};
}

/// The admin's numbers for everyone.
async function saveConfig(db, data = {}) {
  const daily = data.dailyTarget == null || data.dailyTarget === '' ? null : Number(data.dailyTarget);
  if (daily !== null && !(Number.isInteger(daily) && daily >= 1 && daily <= 100000)) throw Error('The daily target is a whole number from 1.');
  const monthly = data.monthlyTarget == null || data.monthlyTarget === '' ? null : Number(data.monthlyTarget);
  if (monthly !== null && !(Number.isInteger(monthly) && monthly >= 1)) throw Error('The monthly target is a whole number from 1, or empty (daily target x days).');
  const slabs = R.cleanSlabs(data.slabs ?? []);
  const config = {dailyTarget: daily ?? R.DEFAULT_DAILY_TARGET, monthlyTarget: monthly, slabs, updatedAt: FieldValue.serverTimestamp()};
  await db.collection('staffPayConfig').doc('main').set(config);
  return {dailyTarget: config.dailyTarget, monthlyTarget: monthly, slabs};
}

/// One staff member's own numbers (null fields: the same as everyone).
async function saveStaffTargets(db, data = {}) {
  if (typeof data.staffUid !== 'string' || !ID.test(data.staffUid)) throw Error('Choose the staff member.');
  if (!(await db.collection('fieldStaff').doc(data.staffUid).get()).exists) throw Error('Staff member not found.');
  const pick = (v, label) => {
    if (v == null || v === '') return null;
    const n = Number(v);
    if (!Number.isInteger(n) || n < 1) throw Error(`The ${label} is a whole number from 1, or empty.`);
    return n;
  };
  const own = {dailyTarget: pick(data.dailyTarget, 'daily target'), monthlyTarget: pick(data.monthlyTarget, 'monthly target'), slabs: R.cleanSlabs(data.slabs ?? null)};
  await db.collection('staffPayTargets').doc(data.staffUid).set({...own, updatedAt: FieldValue.serverTimestamp()});
  return own;
}

/// One staff member's month: updates, targets and pay.
async function staffMonth(db, staffUid, month, config) {
  const [own, monthDoc] = await Promise.all([
    db.collection('staffPayTargets').doc(staffUid).get(),
    db.collection('staffWork').doc(staffUid).collection('months').doc(month).get(),
  ]);
  const m = monthDoc.data() || {};
  const targets = R.targetsFor(config, own.data() || {}, month);
  return {month, updates: m.updates || 0, items: m.items || 0, prices: m.prices || 0, offers: m.offers || 0,
    activeVendors: Object.keys(m.vendors || {}).length, targets, pay: R.payFor(m.updates || 0, targets)};
}

/// Payout methods. Only "manual" now: the admin pays by hand and marks it. A bank transfer can be added here later as one more method,
/// without touching how the amount is worked out.
const PAYOUT_METHODS = {
  manual: async ({note}) => ({reference: String(note ?? '').trim().slice(0, 200)}),
};

/// The admin marks a staff member's month paid (the amount is worked out again here), or not paid.
async function markPaid(db, adminUid, data = {}, now = Date.now()) {
  if (typeof data.staffUid !== 'string' || !ID.test(data.staffUid)) throw Error('Choose the staff member.');
  if (!/^\d{4}-\d{2}$/.test(String(data.month))) throw Error('Choose the month.');
  const ref = db.collection('staffPayouts').doc(`${data.staffUid}_${data.month}`);
  if (data.paid === false) {
    await ref.set({status: 'unpaid', undoneAt: Timestamp.fromMillis(now), undoneBy: adminUid}, {merge: true});
    return {status: 'unpaid'};
  }
  const method = PAYOUT_METHODS[data.method || 'manual'];
  if (!method) throw Error('Unknown payment method.');
  const staff = (await db.collection('fieldStaff').doc(data.staffUid).get()).data();
  if (!staff) throw Error('Staff member not found.');
  const work = await staffMonth(db, data.staffUid, data.month, await payConfig(db));
  const amount = data.amount == null || data.amount === '' ? work.pay.amount : Number(data.amount);
  if (!Number.isFinite(amount) || amount < 0) throw Error('Enter the amount paid.');
  const result = await method({note: data.note, amount, staff});
  const payout = {
    staffUid: data.staffUid, staffCode: staff.staffCode || '', staffName: staff.name || '', month: data.month,
    updates: work.updates, target: work.targets.monthly, percent: work.pay.percent, slabPercent: work.pay.slab?.percent ?? 0,
    worked: work.pay.amount, amount, method: data.method || 'manual', reference: result.reference || '',
    status: 'paid', paidAt: Timestamp.fromMillis(now), paidBy: adminUid,
  };
  await ref.set(payout);
  return {...payout, paidAt: iso(payout.paidAt)};
}

/// Every staff member for the admin: ID, phone, area, the people linked to them (IDs and phones), today's and this month's updates,
/// targets and pay. [areaId] keeps only one area.
async function overview(db, {month, areaId = '', now = Date.now()} = {}) {
  month = /^\d{4}-\d{2}$/.test(String(month)) ? month : R.monthKey(now);
  const today = R.dayKey(now);
  const [staffSnap, linksSnap, areaStaffSnap, areasSnap, config] = await Promise.all([
    db.collection('fieldStaff').get(), db.collection('staffLinks').get(), db.collection('staffAreaStaff').get(), db.collection('staffAreas').get(), payConfig(db),
  ]);
  const areaOf = Object.fromEntries(areaStaffSnap.docs.map(d => [d.id, d.data().areaId || '']));
  const areaName = Object.fromEntries(areasSnap.docs.map(d => [d.id, d.data().name || d.id]));
  const linksBy = {};
  for (const l of linksSnap.docs.map(d => d.data())) (linksBy[l.staffUid] ||= []).push(l);
  const rows = [];
  for (const doc of staffSnap.docs) {
    const s = doc.data();
    if (areaId && areaOf[doc.id] !== areaId) continue;
    const links = linksBy[doc.id] || [];
    const people = [];
    for (const l of links) {
      const record = (await db.collection(l.kind === 'provider' ? 'providerApplications' : 'vendorApplications').doc(l.accountUid).get()).data() || {};
      people.push({kind: l.kind, accountUid: l.accountUid, code: l.code || '', name: l.name || record.name || '', phone: record.phone || '', town: l.town || ''});
    }
    const [work, todayDoc, own] = await Promise.all([
      staffMonth(db, doc.id, month, config),
      db.collection('staffWork').doc(doc.id).collection('days').doc(today).get(),
      db.collection('staffPayTargets').doc(doc.id).get(),
    ]);
    const todayUpdates = todayDoc.data()?.updates || 0;
    rows.push({
      staffUid: doc.id, staffCode: s.staffCode || '', name: s.name || '', phone: s.phone || '', status: s.status || '',
      areaId: areaOf[doc.id] || '', areaName: areaName[areaOf[doc.id]] || '', linked: people.length, people,
      today: todayUpdates, dailyTarget: work.targets.daily, todayPercent: work.targets.daily ? Math.round((todayUpdates / work.targets.daily) * 100) : 0,
      month: work, ownNumbers: own.exists,
    });
  }
  return {month, today, config: {dailyTarget: config.dailyTarget ?? R.DEFAULT_DAILY_TARGET, monthlyTarget: config.monthlyTarget ?? null, slabs: config.slabs || []},
    areas: areasSnap.docs.map(d => ({id: d.id, name: d.data().name || d.id})), rows};
}

/// The month's ranking: most updates, then most active vendors, then most of the target done.
async function ranking(db, opts = {}) {
  const data = await overview(db, opts);
  data.rows.sort((a, b) => b.month.updates - a.month.updates || b.month.activeVendors - a.month.activeVendors || b.month.pay.percent - a.month.pay.percent);
  data.rows.forEach((r, i) => { r.rank = i + 1; });
  return data;
}

/// Days of a person's or staff member's activity from [fromDay] on.
async function days(col, fromDay) {
  const snap = await col.where(FieldPath.documentId(), '>=', fromDay).get();
  return snap.docs.map(d => ({day: d.id, updates: d.data().updates || 0, items: d.data().items || 0, prices: d.data().prices || 0, offers: d.data().offers || 0}));
}
async function months(col) {
  return (await col.get()).docs.map(d => ({month: d.id, updates: d.data().updates || 0, items: d.data().items || 0, prices: d.data().prices || 0, offers: d.data().offers || 0}));
}

/// The read-only report of one Vendor ID (VEN-...), service provider ID (SRV-...) or Staff ID (STF-...).
async function idReport(db, rawCode, now = Date.now()) {
  const code = String(rawCode ?? '').trim().toUpperCase();
  const from = R.dayKey(now - 400 * 86400000);
  if (/^STF-/.test(code)) {
    const found = await db.collection('fieldStaff').where('staffCode', '==', code).limit(1).get();
    if (found.empty) throw Error(`No staff member has the ID ${code}.`);
    const uid = found.docs[0].id, s = found.docs[0].data();
    const month = R.monthKey(now);
    const [links, work, dayList, monthList, payouts] = await Promise.all([
      db.collection('staffLinks').where('staffUid', '==', uid).get(), staffMonth(db, uid, month, await payConfig(db)),
      days(db.collection('staffWork').doc(uid).collection('days'), from), months(db.collection('staffWork').doc(uid).collection('months')),
      db.collection('staffPayouts').where('staffUid', '==', uid).get(),
    ]);
    const people = [];
    for (const l of links.docs.map(d => d.data())) {
      const record = (await db.collection(l.kind === 'provider' ? 'providerApplications' : 'vendorApplications').doc(l.accountUid).get()).data() || {};
      people.push({kind: l.kind, code: l.code || '', name: l.name || record.name || '', phone: record.phone || '', linkedAt: iso(l.linkedAt), linkedBy: l.linkedBy || 'staff'});
    }
    return {kind: 'staff', code, uid, name: s.name || '', phone: s.phone || '', status: s.status || '', town: s.town || '', linked: people,
      month: work, days: dayList, months: monthList,
      payouts: payouts.docs.map(d => ({...d.data(), paidAt: iso(d.data().paidAt), undoneAt: iso(d.data().undoneAt)})).sort((a, b) => String(b.month).localeCompare(String(a.month)))};
  }
  const kind = /^VEN-/.test(code) ? 'vendor' : /^SRV-/.test(code) ? 'provider' : null;
  if (!kind) throw Error('Enter a Vendor ID (VEN-...), a service provider ID (SRV-...) or a Staff ID (STF-...).');
  const [appCol, field] = kind === 'vendor' ? ['vendorApplications', 'vendorCode'] : ['providerApplications', 'providerCode'];
  const found = await db.collection(appCol).where(field, '==', code).limit(1).get();
  if (found.empty) throw Error(`No registration has the ID ${code}.`);
  const uid = found.docs[0].id, app = found.docs[0].data();
  const record = (await db.collection(kind === 'vendor' ? 'vendors' : 'providers').doc(uid).get()).data() || {};
  const itemsCol = kind === 'vendor' ? 'products' : 'services';
  const [items, changes, offers, boxes, ads, link, reports, dayList, monthList, shops] = await Promise.all([
    db.collection(itemsCol).where(kind === 'vendor' ? 'ownerId' : 'providerId', '==', uid).limit(300).get(),
    db.collection('vendorChanges').where('vendorId', '==', uid).limit(300).get(),
    db.collection('vendorOffers').where('vendorId', '==', uid).limit(100).get(),
    db.collection('vendorTodaysOffers').where('vendorId', '==', uid).limit(20).get(),
    db.collection('ads').where('vendorId', '==', uid).limit(50).get(),
    db.collection('staffLinks').doc(`${kind}_${uid}`).get(),
    db.collection('abuseTargets').doc(`${kind}_${uid}`).get(),
    days(db.collection('vendorActivity').doc(uid).collection('days'), from),
    months(db.collection('vendorActivity').doc(uid).collection('months')),
    kind === 'vendor' ? db.collection('shops').where('ownerId', '==', uid).limit(1).get() : Promise.resolve(null),
  ]);
  const adRows = [];
  for (const ad of ads.docs) {
    const stats = (await db.collection('adStats').doc(ad.id).get()).data() || {};
    adRows.push({id: ad.id, title: ad.data().title || '', views: stats.views || 0, taps: stats.taps || 0, startsAt: iso(ad.data().startsAt), endsAt: iso(ad.data().endsAt)});
  }
  const shop = shops?.docs?.[0]?.data() || null;
  const listing = items.docs[0]?.data() || {};
  const ratingSource = kind === 'vendor' ? shop || {} : listing;
  const lastDay = dayList.length ? dayList[dayList.length - 1].day : null;
  const last30 = dayList.filter(d => d.day >= R.dayKey(now - 30 * 86400000));
  return {
    kind, code, uid, name: record.name || app.name || '', phone: app.phone || record.phone || '', whatsapp: app.whatsapp || '', status: record.status || app.status || '',
    town: app.town || '', pincode: app.pincode || '', area: app.gpsAddress || app.address || '',
    linkedStaff: link.exists ? {staffCode: link.data().staffCode || '', staffName: link.data().staffName || '', linkedAt: iso(link.data().linkedAt), linkedBy: link.data().linkedBy || 'staff'} : null,
    items: items.docs.map(d => ({id: d.id, name: d.data().name || '', price: d.data().price ?? null, priceSetAt: iso(d.data().priceSetAt), active: d.data().active !== false})),
    priceChanges: changes.docs.map(d => d.data()).filter(c => ['price', 'newProduct', 'product'].includes(c.type))
      .map(c => ({type: c.type, item: c.newValue?.name || c.oldValue?.name || c.docId || '', from: c.oldValue?.price ?? null, to: c.newValue?.price ?? null, at: iso(c.updatedAt), status: c.status || ''}))
      .sort((a, b) => String(b.at).localeCompare(String(a.at))).slice(0, 200),
    offers: [...offers.docs.map(d => ({kind: 'offer', title: d.data().title || '', price: d.data().offerPrice ?? null, status: d.data().status || '', endsAt: iso(d.data().endsAt)})),
      ...boxes.docs.map(d => ({kind: "Today's Offers", title: d.data().name || '', price: d.data().price ?? null, status: 'live', endsAt: iso(d.data().endsAt)}))],
    ads: adRows,
    ratings: {avg: ratingSource.ratingAvg || 0, count: ratingSource.ratingCount || 0},
    reports: reports.exists ? {count: reports.data().count || 0, state: reports.data().state || 'ok'} : {count: 0, state: 'none'},
    activity: {lastUpdateDay: lastDay, last30Days: last30.reduce((s, d) => s + d.updates, 0), activeDays30: last30.filter(d => d.updates > 0).length},
    days: dayList, months: monthList,
  };
}

module.exports = {recordUpdate, linkedStaff, saveConfig, saveStaffTargets, staffMonth, markPaid, overview, ranking, idReport, PAYOUT_METHODS};
