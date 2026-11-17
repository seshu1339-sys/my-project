'use strict';
// The admin billing alert (free-limit plan, owner OK 17 Nov 2026): the Google Cloud budgets send their status to the Pub/Sub topic
// "billing-alerts" (several times a day). When a budget passes a NEW threshold this month (50 %, 80 %, 100 %…), the admin panel gets a
// red line (healthAlerts/billing~<budget>) and a push to every admin device. Nothing is stopped: alerts only.
//
//   billingAlerts/<budget>~<month>   {threshold, cost, budget, at}   the highest threshold already alerted this month (functions only)
//   billingStatus/current            {budgets: {<budget>: {name, cost, budget, currency, month, at}}}   the latest spend of each budget
// Pub/Sub is free for this (a few small messages a day, far under 10 GB a month).
const {Timestamp} = require('firebase-admin/firestore');
const {pushAdmins} = require('./alerts');

const safe = v => String(v || 'budget').replace(/[^A-Za-z0-9 _-]/g, '_').slice(0, 80);
const money = (n, currency) => `${currency === 'INR' ? '₹' : `${currency || ''} `}${Number(n || 0).toFixed(2)}`;

/// Handles one budget message ([data] is the JSON Google sends). Returns true when the admin was alerted.
async function onBudgetMessage(db, data, now = Date.now(), {send} = {}) {
  // Every message (several a day): this month's spend per budget, for the Health page's "Spent this month".
  if (data && data.costAmount != null) {
    await db.collection('billingStatus').doc('current').set({
      budgets: {[safe(data.budgetDisplayName)]: {
        name: String(data.budgetDisplayName || 'budget').slice(0, 80), cost: Number(data.costAmount || 0), budget: Number(data.budgetAmount || 0),
        currency: String(data.currencyCode || 'INR'), month: String(data.costIntervalStart || '').slice(0, 7), at: Timestamp.fromMillis(now),
      }},
    }, {merge: true});
  }
  const threshold = Number(data?.alertThresholdExceeded);
  if (!Number.isFinite(threshold) || threshold <= 0) return false; // a status message under every threshold
  const name = safe(data.budgetDisplayName);
  const month = String(data.costIntervalStart || new Date(now).toISOString()).slice(0, 7);
  const ref = db.collection('billingAlerts').doc(`${name}~${month}`);
  const isNew = await db.runTransaction(async tx => {
    const before = Number((await tx.get(ref)).data()?.threshold || 0);
    if (threshold <= before) return false;
    tx.set(ref, {threshold, cost: Number(data.costAmount || 0), budget: Number(data.budgetAmount || 0), at: Timestamp.fromMillis(now)});
    return true;
  });
  if (!isNew) return false;
  const cost = money(data.costAmount, data.currencyCode);
  const budget = money(data.budgetAmount, data.currencyCode);
  const message = `Google Cloud this month: ${cost} spent, ${Math.round(threshold * 100)}% of the "${data.budgetDisplayName || 'budget'}" budget (${budget}). Check Billing > Reports.`;
  await db.collection('healthAlerts').doc(`billing~${name}`).set({open: true, type: 'billing', problemId: '', app: 'admin', platform: 'web', kind: 'billing', side: 'our', message, n: 0, minutes: 0, at: Timestamp.fromMillis(now)});
  await pushAdmins(db, `💰 ${cost}: ${Math.round(threshold * 100)}% of ${data.budgetDisplayName || 'budget'}`, message, {send});
  return true;
}

module.exports = {onBudgetMessage};
