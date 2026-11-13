'use strict';
// What the Plans module reads and writes.
//
//   vendorPlans/<id>            the plans the admin made; the vendor app shows these names and prices as they are
//   planServiceGates/main       which special services need a plan (all off until the admin switches them on)
//   vendorPlanPeriods/<reqId>   one bought plan, with the name, price and duration of the day it was chosen
//   vendorPlanStatus/<uid>      the vendor's latest end date and item limit, read by the vendor app and functions/plan-gate.js
//
// A plan starts either from a verified payment (activatePlan) or from the admin by hand (adminActivatePlan, source 'admin'); the admin
// can also stop a running plan (adminStopPlan). Both write the same vendorPlanStatus, so the rest of the system cannot tell them apart.
//
// Plans meets the payment module only in paymentRequests/<reqId>. Plans creates the document with {uid, source: 'plans', amount, label,
// status: 'awaiting_payment'}. The payment module moves status on (checking, manual_review, then verified, rejected or cancelled) and,
// when verified, adds paidAt. Neither side imports the other, so the payment method can change without touching this file.
const {Timestamp} = require('firebase-admin/firestore');
const {validatePlan, validateGates, planPeriod, planItemLimit, planBenefits, IST} = require('./rules');

const ID = /^[a-zA-Z0-9_-]{1,128}$/;
const OPEN = ['awaiting_payment', 'checking', 'manual_review'];
const dateText = ms => new Date(ms + IST).toISOString().slice(0, 10).split('-').reverse().join('/');

/// Admin adds a plan, or edits one with planId. A vendor who already chose a plan keeps its price and duration.
async function savePlan(db, data = {}, now = Date.now()) {
  const fields = validatePlan(data);
  const at = Timestamp.fromMillis(now);
  if (data.planId === undefined || data.planId === null || data.planId === '') {
    const ref = db.collection('vendorPlans').doc();
    await ref.set({...fields, createdAt: at, updatedAt: at});
    return {planId: ref.id};
  }
  if (typeof data.planId !== 'string' || !ID.test(data.planId)) throw Error('That plan was not found.');
  const ref = db.collection('vendorPlans').doc(data.planId);
  if (!(await ref.get()).exists) throw Error('That plan was not found.');
  const before = (await ref.get()).data();
  await ref.update({...fields, updatedAt: at});
  // Owner, 13 Nov 2026: a change of boxes, km, photos, items or kind reaches the vendors already on this plan at once. The price and
  // the months only apply to new purchases (a bought plan keeps its own).
  const updated = await syncRunningVendors(db, ref.id, before?.name, fields, now);
  return {planId: ref.id, updated};
}

/// The vendors whose running plan is this one (by plan id; older statuses by plan name) get the plan's new benefits.
async function syncRunningVendors(db, planId, oldName, fields, now) {
  const found = new Map();
  for (const doc of (await db.collection('vendorPlanStatus').where('planId', '==', planId).get()).docs) found.set(doc.id, doc);
  if (oldName) {
    for (const doc of (await db.collection('vendorPlanStatus').where('planName', '==', oldName).get()).docs) {
      if (!doc.data().planId) found.set(doc.id, doc);
    }
  }
  const running = [...found.values()].filter(doc => (doc.data().endsAt?.toMillis?.() ?? 0) > now);
  const at = Timestamp.fromMillis(now);
  for (let i = 0; i < running.length; i += 400) {
    const batch = db.batch();
    for (const doc of running.slice(i, i + 400)) {
      batch.update(doc.ref, {planId, planName: fields.name, itemLimit: fields.itemLimit, ...planBenefits(fields), benefitsSyncedAt: at});
    }
    await batch.commit();
  }
  return running.length;
}

async function saveGates(db, data = {}, now = Date.now()) {
  const gates = validateGates(data);
  await db.collection('planServiceGates').doc('main').set({...gates, updatedAt: Timestamp.fromMillis(now)}, {merge: true});
  return gates;
}

/// Vendor chooses a plan. Makes the payment request, or returns the open one for the same plan and price.
async function startPurchase(db, uid, data = {}, now = Date.now()) {
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (!vendor || vendor.status !== 'approved') throw Error('Only an approved vendor can choose a plan.');
  const {planId} = data;
  if (typeof planId !== 'string' || !ID.test(planId)) throw Error('Choose a plan.');
  const plan = (await db.collection('vendorPlans').doc(planId).get()).data();
  if (!plan || plan.active !== true) throw Error('This plan is not available.');
  const requests = (await db.collection('paymentRequests').where('uid', '==', uid).get()).docs;
  const open = requests.filter(doc => doc.data().source === 'plans' && OPEN.includes(doc.data().status));
  if (open.some(doc => doc.data().status !== 'awaiting_payment')) throw Error('Your last payment is still being checked. Please wait for the result.');
  const periods = await Promise.all(open.map(doc => db.collection('vendorPlanPeriods').doc(doc.id).get()));
  const same = periods.find(doc => doc.data()?.planId === planId && doc.data()?.price === plan.price);
  if (same) return {requestId: same.id, amount: plan.price};
  const at = Timestamp.fromMillis(now);
  const ref = db.collection('paymentRequests').doc();
  const batch = db.batch();
  for (const doc of open) {
    batch.update(doc.ref, {status: 'cancelled', updatedAt: at});
    batch.set(db.collection('vendorPlanPeriods').doc(doc.id), {status: 'cancelled', updatedAt: at}, {merge: true});
  }
  batch.set(ref, {uid, source: 'plans', amount: plan.price, label: `${plan.name} plan`, status: 'awaiting_payment', createdAt: at, updatedAt: at});
  batch.set(db.collection('vendorPlanPeriods').doc(ref.id), {
    uid, planId, planName: plan.name, price: plan.price, durationMonths: plan.durationMonths, itemLimit: planItemLimit(plan), ...planBenefits(plan), status: 'pending', createdAt: at, updatedAt: at,
  });
  await batch.commit();
  return {requestId: ref.id, amount: plan.price};
}

/// The vendor's plan status: who (name and Vendor ID, for the admin's list), the plan, its end and how many items it allows.
const statusFields = (uid, vendor, planName, endsAt, itemLimit, at, source, plan = {}, planId = null) => ({
  uid, vendorName: vendor.name || '', vendorCode: vendor.vendorCode || '', planName, ...(planId ? {planId} : {}), endsAt: Timestamp.fromMillis(endsAt), itemLimit, source, updatedAt: at,
  // The kind (Silver / Gold / Premium), the extra photos, the km and the Today's Offers boxes of the latest plan.
  ...planBenefits(plan),
});
/// A plan added to one still running keeps the bigger of the two item limits.
const itemLimitAfter = (current, period, now) => {
  const running = (current?.endsAt?.toMillis?.() ?? 0) > now;
  return Math.max(planItemLimit(period), running ? planItemLimit(current) : 0);
};

/// A payment was verified. Runs once for one request, however many times it is called.
async function activatePlan(db, requestId, request, now = Date.now()) {
  const periodRef = db.collection('vendorPlanPeriods').doc(requestId);
  return db.runTransaction(async tx => {
    const period = (await tx.get(periodRef)).data();
    if (!period || period.status !== 'pending' || period.uid !== request.uid) return null;
    const statusRef = db.collection('vendorPlanStatus').doc(period.uid);
    const current = (await tx.get(statusRef)).data();
    const vendor = (await tx.get(db.collection('vendors').doc(period.uid))).data() || {};
    const paidAt = Math.min(request.paidAt?.toMillis?.() ?? now, now);
    const {startsAt, endsAt} = planPeriod(paidAt, period.durationMonths, current?.endsAt?.toMillis?.() ?? 0);
    const at = Timestamp.fromMillis(now);
    tx.update(periodRef, {status: 'active', paidAt: Timestamp.fromMillis(paidAt), startsAt: Timestamp.fromMillis(startsAt), endsAt: Timestamp.fromMillis(endsAt), updatedAt: at});
    tx.set(statusRef, statusFields(period.uid, vendor, period.planName, endsAt, itemLimitAfter(current, period, now), at, 'payment', period, period.planId));
    tx.set(db.collection('vendorNotices').doc(), {
      vendorId: period.uid, type: 'plan', title: 'Your plan is active', body: `${period.planName}: from ${dateText(startsAt)} to ${dateText(endsAt)}.`, createdAt: at,
    });
    return {startsAt, endsAt};
  });
}

/// The vendor for the admin: by Vendor ID (VEN-NRPM-116-325) or by uid.
async function findVendor(db, data) {
  const code = typeof data.vendorCode === 'string' ? data.vendorCode.trim().toUpperCase() : '';
  if (code) {
    const found = await db.collection('vendors').where('vendorCode', '==', code).limit(1).get();
    if (found.empty) throw Error(`No vendor has the ID ${code}.`);
    return found.docs[0];
  }
  if (typeof data.uid !== 'string' || !ID.test(data.uid)) throw Error('Enter the Vendor ID.');
  const doc = await db.collection('vendors').doc(data.uid).get();
  if (!doc.exists) throw Error('That vendor was not found.');
  return doc;
}

/// Admin starts a plan for a vendor by hand (no payment in the app): from now, or when the running plan ends, for the plan's full
/// duration. The vendor is told, like after a payment.
async function adminActivatePlan(db, data = {}, adminUid = '', now = Date.now()) {
  const vendorDoc = await findVendor(db, data);
  const vendor = vendorDoc.data();
  if (vendor.status !== 'approved') throw Error('Only an approved vendor can have a plan.');
  if (typeof data.planId !== 'string' || !ID.test(data.planId)) throw Error('Choose a plan.');
  const plan = (await db.collection('vendorPlans').doc(data.planId).get()).data();
  if (!plan) throw Error('That plan was not found.');
  const uid = vendorDoc.id;
  const statusRef = db.collection('vendorPlanStatus').doc(uid);
  return db.runTransaction(async tx => {
    const current = (await tx.get(statusRef)).data();
    const {startsAt, endsAt} = planPeriod(now, plan.durationMonths, current?.endsAt?.toMillis?.() ?? 0);
    const at = Timestamp.fromMillis(now);
    const period = {uid, planId: data.planId, planName: plan.name, price: plan.price, durationMonths: plan.durationMonths, itemLimit: planItemLimit(plan), ...planBenefits(plan)};
    tx.set(db.collection('vendorPlanPeriods').doc(), {
      ...period, status: 'active', source: 'admin', activatedBy: adminUid, startsAt: Timestamp.fromMillis(startsAt), endsAt: Timestamp.fromMillis(endsAt), createdAt: at, updatedAt: at,
    });
    tx.set(statusRef, statusFields(uid, vendor, plan.name, endsAt, itemLimitAfter(current, period, now), at, 'admin', plan, data.planId));
    tx.set(db.collection('vendorNotices').doc(), {
      vendorId: uid, type: 'plan', title: 'Your plan is active', body: `${plan.name}: from ${dateText(startsAt)} to ${dateText(endsAt)}.`, createdAt: at,
    });
    return {uid, startsAt, endsAt};
  });
}

/// Admin stops a vendor's running plan now (and any renewal waiting after it). The shop stays live; only the plan's services stop.
async function adminStopPlan(db, data = {}, adminUid = '', now = Date.now()) {
  const vendorDoc = await findVendor(db, data);
  const uid = vendorDoc.id;
  const statusRef = db.collection('vendorPlanStatus').doc(uid);
  const periods = await db.collection('vendorPlanPeriods').where('uid', '==', uid).where('status', '==', 'active').get();
  return db.runTransaction(async tx => {
    const current = (await tx.get(statusRef)).data();
    if ((current?.endsAt?.toMillis?.() ?? 0) <= now) throw Error('This vendor has no running plan.');
    const at = Timestamp.fromMillis(now);
    for (const doc of periods.docs) {
      if ((doc.data().endsAt?.toMillis?.() ?? 0) > now) tx.update(doc.ref, {status: 'stopped', stoppedAt: at, stoppedBy: adminUid, updatedAt: at});
    }
    tx.set(statusRef, {endsAt: at, stoppedAt: at, stoppedBy: adminUid, source: 'admin', updatedAt: at}, {merge: true});
    tx.set(db.collection('vendorNotices').doc(), {
      vendorId: uid, type: 'plan', title: 'Your plan has ended', body: `${current.planName || 'Your plan'} was stopped by the LOCAMARKET team. Your shop stays live.`, createdAt: at,
    });
    return {uid};
  });
}

module.exports = {savePlan, saveGates, startPurchase, activatePlan, adminActivatePlan, adminStopPlan};
