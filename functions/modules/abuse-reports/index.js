'use strict';
// Abuse reports module (owner, 13 Nov 2026). Customers report a shop or a service provider they really dealt with; vendors report a
// customer who ordered from them. Each person reports each other one once. When the reports about one shop, provider or customer reach
// the admin's number (settings/business.abuseReportsToSuspend, 10 when not set), the account is suspended at once, for a while only:
// the admin is told (an alert in the admin panel and an email) and then restores it or blocks it for good. Only the admin blocks for
// good; a blocked email or phone cannot register again (functions/block-list.js). The same rule for vendors, providers and customers.
//
//   reportAbuse         customer: {kind: 'shop', shopId} | {kind: 'provider', listingId}; vendor: {kind: 'customer', orderId}
//                       + {reason, details}
//   decideAbuseTarget   admin -> {targetKey, action: 'restore' | 'block'}
//   blockContact        admin -> {email | phone, reason}      unblockContact admin -> {key}
//
//   abuseReports/<targetKey>_<reporter>  {targetKey, kind, targetId, reason, details, reporterRole, at}       admin only
//   abuseTargets/<targetKey>             {kind, targetId, label, count, countAtRestore, state, lastAt, ...}  admin only
//   adminAlerts/<id>                     {type: 'autoSuspension', targetKey, label, count, at, read}       admin only
// targetKey is "vendor_<uid>", "provider_<uid>" or "customer_<uid>". Who reported whom is never shown to the person reported.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret, defineString} = require('firebase-functions/params');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {requireRole, isAdminToken} = require('../../role-auth');
const {requireAdminSession} = require('../../admin-session');
const {setCatalogVisibility} = require('../../catalog-visibility');
const {blockContacts, contactKeys} = require('../../block-list');
const {_accountSwitch} = require('../../inactive-accounts');

const mailUser = defineString('ADMIN_MAIL_USER');
const mailPassword = defineSecret('ADMIN_MAIL_PASSWORD');
const options = {region: 'us-central1', maxInstances: 5, invoker: 'public'};
const DEFAULT_REPORTS_TO_SUSPEND = 10;
const REASONS = ['cheating', 'abuse', 'fake', 'no_show', 'other'];
const PERSON_EVENTS = ['worker_call', 'worker_whatsapp'];
const ID = /^[A-Za-z0-9_-]{1,128}$/;

/// The admin's number of reports for an automatic suspension (1 to 1000), 10 when not set.
function reportsToSuspend(business) {
  const n = Math.round(Number(business?.abuseReportsToSuspend));
  return Number.isFinite(n) && n >= 1 && n <= 1000 ? n : DEFAULT_REPORTS_TO_SUSPEND;
}

/// Whether this report makes the target reach the number since its last restore (a suspended or blocked one is left as it is).
const reachesSuspension = (target, threshold) => !['suspended', 'blocked'].includes(target.state) && target.count - (target.countAtRestore || 0) >= threshold;

const fail = (message, code = 'failed-precondition') => { throw new HttpsError(code, message); };

/// Who is reported and whether the reporter really dealt with them. Returns {kind, targetId, label}.
async function resolveTarget(db, reporter, role, data) {
  const kind = data.kind;
  if (role === 'user' && kind === 'shop') {
    if (typeof data.shopId !== 'string' || !ID.test(data.shopId)) fail('Choose the shop.', 'invalid-argument');
    const shop = (await db.collection('shops').doc(data.shopId).get()).data();
    if (!shop?.ownerId) fail('This shop cannot be reported.');
    // Only a customer who ordered from this shop.
    const orders = await db.collection('orders').where('userId', '==', reporter).get();
    if (!orders.docs.some(doc => (doc.data().shopIds || []).includes(data.shopId))) fail('Only a customer who ordered from this shop can report it.');
    return {kind: 'vendor', targetId: shop.ownerId, label: shop.name || data.shopId};
  }
  if (role === 'user' && kind === 'provider') {
    if (typeof data.listingId !== 'string' || !ID.test(data.listingId)) fail('Choose the service.', 'invalid-argument');
    const listing = (await db.collection('services').doc(data.listingId).get()).data();
    const providerId = listing?.providerId || listing?.ownerId;
    if (!providerId) fail('This service cannot be reported.');
    // Services are booked by calling: only a customer who called or messaged this provider from the app (the per-person usage days).
    const days = await db.collection('usagePersonDaily').where('uid', '==', reporter).get();
    const dealt = days.docs.some(doc => Object.values(doc.data().keys || {}).some(k => PERSON_EVENTS.includes(k.event) && k.key === data.listingId));
    if (!dealt) fail('Only a customer who called or messaged this service provider from the app can report them.');
    return {kind: 'provider', targetId: providerId, label: listing.name || providerId};
  }
  if (role === 'vendor' && kind === 'customer') {
    if (typeof data.orderId !== 'string' || !ID.test(data.orderId)) fail('Choose the order.', 'invalid-argument');
    const [order, vendor] = await Promise.all([db.collection('orders').doc(data.orderId).get(), db.collection('vendors').doc(reporter).get()]);
    const shopId = vendor.data()?.shopId;
    if (!order.exists || !shopId || !(order.data().shopIds || []).includes(shopId)) fail('Only a vendor who got this order can report its customer.');
    const customer = order.data().userId;
    if (!customer) fail('This order has no customer account.');
    const profile = (await db.collection('users').doc(customer).get()).data() || {};
    return {kind: 'customer', targetId: customer, label: profile.name || `Customer of order ${data.orderId.slice(0, 8)}`};
  }
  fail('This cannot be reported here.', 'invalid-argument');
}

/// Suspends (hide) or restores (show) the target. Vendors and providers: their status and their listings; customers: their sign-in.
async function setSuspended(db, kind, targetId, suspended, by) {
  const at = FieldValue.serverTimestamp();
  if (kind === 'vendor' || kind === 'provider') {
    const ref = db.collection(kind === 'vendor' ? 'vendors' : 'providers').doc(targetId);
    const record = (await ref.get()).data();
    if (!record) return 0;
    if (suspended && record.status === 'approved') {
      await ref.update({status: 'suspended', suspensionReason: 'Many reports: waiting for the administrator', autoSuspended: true, suspendedAt: at, suspendedBy: by});
    }
    if (!suspended && record.status === 'suspended') {
      await ref.update({status: 'approved', reinstatedAt: at, reinstatedBy: by, suspensionReason: FieldValue.delete(), autoSuspended: FieldValue.delete()});
    }
    return setCatalogVisibility(db, targetId, kind === 'vendor' ? record.shopId : null, suspended);
  }
  await _accountSwitch.setDisabled(targetId, suspended, by);
  return 1;
}

/// The emails and phone numbers of a target, for the permanent block list.
async function contactsOf(db, kind, targetId) {
  const emails = [], phones = [];
  const add = (data = {}) => { emails.push(data.email); phones.push(data.phone, data.whatsapp); };
  if (kind === 'vendor') for (const name of ['vendors', 'vendorApplications']) add((await db.collection(name).doc(targetId).get()).data());
  if (kind === 'provider') for (const name of ['providers', 'providerApplications']) add((await db.collection(name).doc(targetId).get()).data());
  if (kind === 'customer') {
    add((await db.collection('users').doc(targetId).get()).data());
    const user = await getAuth().getUser(targetId).catch(() => null);
    emails.push(user?.email, user?.customClaims?.loginEmail);
    phones.push(user?.phoneNumber);
  }
  return {emails: emails.filter(Boolean), phones: phones.filter(Boolean)};
}

/// Tells the admin: an alert in the admin panel and an email (EMAIL_DRY_RUN=true records it instead, as the other mails do).
async function tellAdmin(db, alert) {
  await db.collection('adminAlerts').add({...alert, read: false, at: FieldValue.serverTimestamp()});
  const subject = `LOCAMARKET: ${alert.label} suspended after ${alert.count} reports`;
  const text = `${alert.label} (${alert.kind}) got ${alert.count} reports and is suspended for now. Open the admin panel > Reports to restore it or block it for good.`;
  try {
    if (process.env.EMAIL_DRY_RUN === 'true') { await db.collection('_emailDryRun').add({to: 'admin', subject, text, createdAt: FieldValue.serverTimestamp()}); return; }
    const nodemailer = require('nodemailer');
    const transport = nodemailer.createTransport({service: 'gmail', auth: {user: mailUser.value(), pass: mailPassword.value()}});
    await transport.sendMail({from: mailUser.value(), to: mailUser.value(), subject, text});
  } catch (error) {
    console.warn('Admin email not sent', error.message);
  }
}

/// One report. Returns {count, suspended}.
async function report(db, reporter, role, data = {}, now = Date.now()) {
  const reason = REASONS.includes(data.reason) ? data.reason : fail('Choose why you are reporting.', 'invalid-argument');
  const details = String(data.details ?? '').trim().slice(0, 500);
  const target = await resolveTarget(db, reporter, role, data);
  if (target.targetId === reporter) fail('You cannot report yourself.');
  const targetKey = `${target.kind}_${target.targetId}`;
  const threshold = reportsToSuspend((await db.collection('settings').doc('business').get()).data());
  const reportRef = db.collection('abuseReports').doc(`${targetKey}_${reporter}`);
  const targetRef = db.collection('abuseTargets').doc(targetKey);
  const result = await db.runTransaction(async tx => {
    if ((await tx.get(reportRef)).exists) fail('You have already reported this. The Support Team will look at it.', 'already-exists');
    const current = (await tx.get(targetRef)).data() || {state: 'ok', count: 0, countAtRestore: 0};
    const next = {...current, kind: target.kind, targetId: target.targetId, label: target.label, count: (current.count || 0) + 1, lastAt: Timestamp.fromMillis(now)};
    const suspend = reachesSuspension(next, threshold);
    if (suspend) Object.assign(next, {state: 'suspended', autoSuspendedAt: Timestamp.fromMillis(now)});
    tx.set(reportRef, {targetKey, kind: target.kind, targetId: target.targetId, reason, details, reporterRole: role, reporterUid: reporter, at: Timestamp.fromMillis(now)});
    tx.set(targetRef, next);
    return {count: next.count, suspended: suspend};
  });
  if (result.suspended) {
    await setSuspended(db, target.kind, target.targetId, true, 'reports');
    await tellAdmin(db, {type: 'autoSuspension', targetKey, kind: target.kind, label: target.label, count: result.count});
  }
  return result;
}

/// The admin's decision on a suspended (or any reported) target: restore it, or block it for good (it stays suspended and its emails
/// and phones go on the block list).
async function decide(db, adminUid, data = {}, now = Date.now()) {
  const targetKey = String(data.targetKey ?? '');
  const ref = db.collection('abuseTargets').doc(targetKey);
  const target = (await ref.get()).data();
  if (!target) fail('Report not found.', 'not-found');
  if (data.action === 'restore') {
    await setSuspended(db, target.kind, target.targetId, false, adminUid);
    await ref.update({state: 'restored', countAtRestore: target.count, decidedBy: adminUid, decidedAt: Timestamp.fromMillis(now)});
    return {state: 'restored'};
  }
  if (data.action === 'block') {
    await setSuspended(db, target.kind, target.targetId, true, adminUid);
    const keys = await blockContacts(db, await contactsOf(db, target.kind, target.targetId), {reason: `${target.count} reports: ${target.label}`, by: adminUid});
    await ref.update({state: 'blocked', blockedKeys: keys, decidedBy: adminUid, decidedAt: Timestamp.fromMillis(now)});
    return {state: 'blocked', blockedKeys: keys};
  }
  fail('Choose restore or block.', 'invalid-argument');
}

async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
  return request.auth.uid;
}

exports.reportAbuse = onCall({...options, secrets: [mailPassword]}, async request => {
  const uid = requireRole(request, ['user', 'vendor']);
  return report(getFirestore(), uid, request.auth.token.role, request.data || {});
});

exports.decideAbuseTarget = onCall({...options, timeoutSeconds: 120}, async request => {
  const uid = await requireAdmin(request);
  return decide(getFirestore(), uid, request.data || {});
});

exports.blockContact = onCall(options, async request => {
  const uid = await requireAdmin(request);
  const {email = '', phone = '', reason = ''} = request.data || {};
  const keys = await blockContacts(getFirestore(), {emails: [email], phones: [phone]}, {reason, by: uid});
  if (!keys.length) throw new HttpsError('invalid-argument', 'Enter an email or a 10-digit phone number.');
  return {keys};
});

exports.unblockContact = onCall(options, async request => {
  await requireAdmin(request);
  const key = String(request.data?.key ?? '');
  if (!/^(email|phone):.{3,200}$/.test(key)) throw new HttpsError('invalid-argument', 'Choose an entry of the block list.');
  await getFirestore().collection('blockedContacts').doc(key).delete();
  return {removed: key};
});

exports._abuse = {report, decide, resolveTarget, reportsToSuspend, reachesSuspension, contactsOf, contactKeys, REASONS, DEFAULT_REPORTS_TO_SUSPEND};
