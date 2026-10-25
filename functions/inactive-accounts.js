'use strict';
// Inactive accounts (Admin > Insights > Analytics > Inactive accounts): the accounts that have not used any app for 7, 30 or 90
// days, with Disable / Enable and Delete, and an automatic daily sweep that is OFF until the admin switches it on.
//   inactiveAccounts      admin -> the accounts inactive for at least N days (not the admin's), most inactive first
//   setAccountDisabled    admin -> disable (cannot sign in) or enable an account
//   deleteInactiveAccount admin -> delete a CUSTOMER account and its personal data (orders stay, as the law needs them);
//                                  vendor, service-provider and staff accounts are disabled or suspended, never deleted here
//   sweepInactiveAccounts daily -> settings/inactiveAccounts {autoDisable, disableAfterDays (30), autoDelete, deleteAfterDays (90)}:
//                                  disables customers inactive for disableAfterDays; deletes customers the sweep disabled who stay
//                                  inactive for deleteAfterDays. Both OFF by default. At most MAX_SWEEP actions a run, each logged
//                                  in inactiveSweeps/<day>.
// "Active" is the latest of: the account's own usage (userActivity, functions/usage.js), its last sign-in and its last token refresh
// (Firebase Auth), and its creation (a new account is not inactive).
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {requireAdminSession} = require('./admin-session');
const {accountKinds} = require('./accounts');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 3, invoker: 'public', timeoutSeconds: 300};

const MAX_LIST = 1000;
const MAX_SWEEP = 200;
const DAY = 86400000;

async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true || request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
}

const millis = value => {
  if (!value) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  const t = Date.parse(value);
  return Number.isFinite(t) ? t : 0;
};

/// The kind of account, in words (customer unless it is a vendor, provider or staff account).
async function kindOf(uid) {
  const k = await accountKinds(db, uid);
  return k.vendor ? 'vendor' : k.provider ? 'service provider' : k.staff ? 'staff' : 'customer';
}

/// Every account (not an admin) inactive for at least [days] days at [now], the most inactive first.
async function findInactive({days, now = Date.now(), limit = MAX_LIST}) {
  const cutoff = now - days * DAY;
  const rows = [];
  let pageToken;
  do {
    const page = await getAuth().listUsers(1000, pageToken);
    const activity = page.users.length ? await db.getAll(...page.users.map(u => db.collection('userActivity').doc(u.uid))) : [];
    page.users.forEach((user, i) => {
      if (user.customClaims?.admin === true) return;
      const last = Math.max(millis(activity[i]?.data()?.lastActiveAt), millis(user.metadata.lastRefreshTime), millis(user.metadata.lastSignInTime), millis(user.metadata.creationTime));
      if (last > cutoff) return;
      rows.push({uid: user.uid, email: user.email || '', name: user.displayName || '', disabled: user.disabled === true, lastActiveAt: last, inactiveDays: Math.floor((now - last) / DAY)});
    });
    pageToken = page.pageToken;
  } while (pageToken && rows.length < limit * 2);
  rows.sort((a, b) => a.lastActiveAt - b.lastActiveAt);
  const out = rows.slice(0, limit);
  for (const row of out) row.kind = await kindOf(row.uid);
  return out;
}

async function setDisabled(uid, disabled, by) {
  await getAuth().updateUser(uid, {disabled});
  await db.collection('accountStates').doc(uid).set({uid, disabled, ...(disabled ? {disabledAt: FieldValue.serverTimestamp(), disabledBy: by} : {enabledAt: FieldValue.serverTimestamp(), enabledBy: by})}, {merge: true});
}

/// Deletes a customer account and its personal data; orders are kept (with the account id only).
async function deleteCustomer(uid) {
  if ((await kindOf(uid)) !== 'customer') throw new HttpsError('failed-precondition', 'Only customer accounts are deleted here. Disable a vendor, provider or staff account, or suspend it.');
  const userRef = db.collection('users').doc(uid);
  for (const sub of await userRef.listCollections()) {
    for (const doc of (await sub.limit(500).get()).docs) await doc.ref.delete();
  }
  await userRef.delete();
  for (const ref of [db.collection('notificationSubscribers').doc(uid), db.collection('userActivity').doc(uid)]) await ref.delete();
  for (const doc of (await db.collection('usagePersonDaily').where('uid', '==', uid).limit(500).get()).docs) await doc.ref.delete();
  try { await getAuth().deleteUser(uid); } catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
  await db.collection('accountStates').doc(uid).set({uid, deleted: true, deletedAt: FieldValue.serverTimestamp()}, {merge: true});
}

exports.inactiveAccounts = onCall(options, async request => {
  await requireAdmin(request);
  const days = Number(request.data?.days);
  if (!Number.isInteger(days) || days < 1 || days > 3650) throw new HttpsError('invalid-argument', 'Choose a number of days.');
  return {accounts: await findInactive({days})};
});

exports.setAccountDisabled = onCall(options, async request => {
  await requireAdmin(request);
  const {uid, disabled} = request.data || {};
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid) || typeof disabled !== 'boolean') throw new HttpsError('invalid-argument', 'Choose the account and disable or enable.');
  if (uid === request.auth.uid) throw new HttpsError('failed-precondition', 'You cannot disable your own account.');
  const user = await getAuth().getUser(uid).catch(() => null);
  if (!user) throw new HttpsError('not-found', 'Account not found.');
  if (user.customClaims?.admin === true) throw new HttpsError('failed-precondition', 'An administrator account is not disabled here.');
  await setDisabled(uid, disabled, request.auth.uid);
  return {uid, disabled};
});

exports.deleteInactiveAccount = onCall(options, async request => {
  await requireAdmin(request);
  const {uid, confirm} = request.data || {};
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) throw new HttpsError('invalid-argument', 'Choose the account.');
  if (confirm !== 'DELETE') throw new HttpsError('invalid-argument', 'Type DELETE to confirm.');
  if (uid === request.auth.uid) throw new HttpsError('failed-precondition', 'You cannot delete your own account.');
  const user = await getAuth().getUser(uid).catch(() => null);
  if (user?.customClaims?.admin === true) throw new HttpsError('failed-precondition', 'An administrator account is not deleted here.');
  await deleteCustomer(uid);
  return {uid, deleted: true};
});

/// One sweep at [now] with the admin's settings. Returns what it did.
async function sweep(now = Date.now()) {
  const settings = (await db.collection('settings').doc('inactiveAccounts').get()).data() || {};
  const disableAfter = Math.max(7, Math.round(Number(settings.disableAfterDays) || 30));
  const deleteAfter = Math.max(disableAfter + 7, Math.round(Number(settings.deleteAfterDays) || 90));
  const done = {disabled: [], deleted: [], at: now};
  if (settings.autoDisable !== true && settings.autoDelete !== true) return done;
  const inactive = await findInactive({days: disableAfter, now, limit: MAX_LIST});
  for (const row of inactive) {
    if (done.disabled.length + done.deleted.length >= MAX_SWEEP) break;
    if (row.kind !== 'customer') continue;
    const state = (await db.collection('accountStates').doc(row.uid).get()).data() || {};
    if (settings.autoDelete === true && row.disabled && state.disabledBy === 'auto-inactive' && row.inactiveDays >= deleteAfter) {
      await deleteCustomer(row.uid);
      done.deleted.push(row.uid);
    } else if (settings.autoDisable === true && !row.disabled) {
      await setDisabled(row.uid, true, 'auto-inactive');
      done.disabled.push(row.uid);
    }
  }
  const day = new Date(now + 19800000).toISOString().slice(0, 10);
  await db.collection('inactiveSweeps').doc(day).set({day, disabled: done.disabled, deleted: done.deleted, disableAfterDays: disableAfter, deleteAfterDays: deleteAfter, at: Timestamp.fromMillis(now)});
  return done;
}

exports.sweepInactiveAccounts = onSchedule({schedule: 'every day 03:30', timeZone: 'Asia/Kolkata', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 540}, () => sweep());

exports._inactive = {findInactive, sweep, deleteCustomer, setDisabled};
