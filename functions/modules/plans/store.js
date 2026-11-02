'use strict';
// What the Plans module reads and writes.
//
//   vendorPlans/<id>            the plans the admin made; the vendor app shows these names and prices as they are
//   planServiceGates/main       which special services need a plan (all off until the admin switches them on)
//   vendorPlanPeriods/<reqId>   one bought plan, with the name, price and duration of the day it was chosen
//   vendorPlanStatus/<uid>      the vendor's latest end date, read by the vendor app and functions/plan-gate.js
//
// Plans meets the payment module only in paymentRequests/<reqId>. Plans creates the document with {uid, source: 'plans', amount, label,
// status: 'awaiting_payment'}. The payment module moves status on (checking, manual_review, then verified, rejected or cancelled) and,
// when verified, adds paidAt. Neither side imports the other, so the payment method can change without touching this file.
const {Timestamp} = require('firebase-admin/firestore');
const {validatePlan, validateGates, planPeriod, IST} = require('./rules');

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
  await ref.update({...fields, updatedAt: at});
  return {planId: ref.id};
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
    uid, planId, planName: plan.name, price: plan.price, durationMonths: plan.durationMonths, status: 'pending', createdAt: at, updatedAt: at,
  });
  await batch.commit();
  return {requestId: ref.id, amount: plan.price};
}

/// A payment was verified. Runs once for one request, however many times it is called.
async function activatePlan(db, requestId, request, now = Date.now()) {
  const periodRef = db.collection('vendorPlanPeriods').doc(requestId);
  return db.runTransaction(async tx => {
    const period = (await tx.get(periodRef)).data();
    if (!period || period.status !== 'pending' || period.uid !== request.uid) return null;
    const statusRef = db.collection('vendorPlanStatus').doc(period.uid);
    const current = (await tx.get(statusRef)).data();
    const paidAt = Math.min(request.paidAt?.toMillis?.() ?? now, now);
    const {startsAt, endsAt} = planPeriod(paidAt, period.durationMonths, current?.endsAt?.toMillis?.() ?? 0);
    const at = Timestamp.fromMillis(now);
    tx.update(periodRef, {status: 'active', paidAt: Timestamp.fromMillis(paidAt), startsAt: Timestamp.fromMillis(startsAt), endsAt: Timestamp.fromMillis(endsAt), updatedAt: at});
    tx.set(statusRef, {uid: period.uid, planName: period.planName, endsAt: Timestamp.fromMillis(endsAt), updatedAt: at});
    tx.set(db.collection('vendorNotices').doc(), {
      vendorId: period.uid, type: 'plan', title: 'Your plan is active', body: `${period.planName}: from ${dateText(startsAt)} to ${dateText(endsAt)}.`, createdAt: at,
    });
    return {startsAt, endsAt};
  });
}

module.exports = {savePlan, saveGates, startPurchase, activatePlan};
