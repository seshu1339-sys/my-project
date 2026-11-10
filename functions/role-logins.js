'use strict';
// A separate login for each role of one email. The person always uses the same email (and the same Google account) in every app; the
// logins are made here, behind the scenes, and nobody ever types a second email.
//
//   1. The app proves the email: "Continue with Google", the 6-digit email code (email-login.js) or the customer app's password. That
//      is the email's own Firebase account. It has NO role, so the database rules and every function refuse it (role-auth.js).
//   2. enterRole({role}) turns that proof into the email's login for that role: a customer ('user'), a 'vendor', a service
//      'provider', field 'staff', or the 'admin' (only for an email set up with functions/set-admin.js). The first time, the login is
//      made, with its own ID and the claims {role, loginEmail}; the app then signs in with the token it gets back.
//   3. switchRole({to}) moves a vendor-app login between Vendor and Service provider (the same email's other login).
//
// Every role login has its own ID, its own records and its own block / delete: blocking one never touches the email's other roles.
// roleLogins/<role>_<sha256(email)> = {role, email, uid, createdAt} remembers which login is which; it is server-only (no client rule).
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {createHash} = require('node:crypto');
const {ROLES, roleOf, loginEmail} = require('./role-auth');

const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const ROLE_WORDS = {user: 'customer', vendor: 'vendor', provider: 'service-provider', staff: 'staff', admin: 'administrator'};
/// The vendor app holds both of these; the person switches between them.
const VENDOR_APP = ['vendor', 'provider'];

const emailKey = email => String(email || '').trim().toLowerCase();
const loginDocId = (role, email) => `${role}_${createHash('sha256').update(emailKey(email)).digest('hex')}`;
const claimsFor = (role, email) => ({role, loginEmail: emailKey(email), ...(role === 'admin' ? {admin: true} : {})});

/// The uid of [email]'s login as [role]. Made the first time unless [create] is false (then '' when there is none).
async function roleLoginFor(role, email, {create = true} = {}) {
  if (!ROLES.includes(role)) throw new Error(`Unknown role: ${role}`);
  const key = emailKey(email);
  if (!key) throw new Error('No email.');
  const ref = db.collection('roleLogins').doc(loginDocId(role, key));
  const existing = (await ref.get()).data()?.uid;
  if (existing) return existing;
  if (!create) return '';
  const auth = getAuth();
  const made = await auth.createUser({});
  await auth.setCustomUserClaims(made.uid, claimsFor(role, key));
  // Two first sign-ins at the same moment: the first one to save wins, the other login is removed again.
  const uid = await db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    if (snapshot.exists) return snapshot.data().uid;
    tx.create(ref, {role, email: key, uid: made.uid, createdAt: FieldValue.serverTimestamp()});
    return made.uid;
  });
  if (uid !== made.uid) await auth.deleteUser(made.uid).catch(() => {});
  return uid;
}

/// Forgets which email and role [uid] was (after the login was deleted), so the next sign-in in that role starts a new, empty login.
async function forgetRoleLogin(uid) {
  const found = await db.collection('roleLogins').where('uid', '==', uid).get();
  await Promise.all(found.docs.map(doc => doc.ref.delete()));
}

/// The email a login belongs to: a role login's loginEmail claim, or the email of the email's own login.
const loginEmailOf = user => String(user?.customClaims?.loginEmail || user?.email || '');

/// A sign-in token for [email]'s login as [role]. A blocked (disabled) login is refused with details {blocked: role}; the email's
/// other roles are not affected.
async function tokenFor(role, email) {
  const key = emailKey(email);
  const uid = await roleLoginFor(role, key, {create: role !== 'admin'});
  if (!uid) throw new HttpsError('permission-denied', 'Administrator access required.');
  const auth = getAuth();
  const user = await auth.getUser(uid);
  if (user.disabled) throw new HttpsError('permission-denied', `Your ${ROLE_WORDS[role]} account is blocked. Contact LOCAMARKET support.`, {blocked: role});
  const claims = user.customClaims || {};
  if (claims.role !== role || claims.loginEmail !== key) await auth.setCustomUserClaims(uid, {...claims, ...claimsFor(role, key)});
  if (role === 'user') {
    // The customer record, made on the first customer sign-in (as before).
    const ref = db.collection('users').doc(uid);
    if (!(await ref.get()).exists) await ref.set({customer: true, email: key, createdAt: FieldValue.serverTimestamp()}, {merge: true});
  }
  return {token: await auth.createCustomToken(uid), role, uid};
}

exports.enterRole = onCall(options, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (roleOf(request)) throw new HttpsError('failed-precondition', 'You are already signed in. Sign out first.');
  const token = request.auth.token;
  if (token.email_verified !== true || !token.email) throw new HttpsError('permission-denied', 'Verify your email first.');
  const role = request.data?.role;
  if (!ROLES.includes(role)) throw new HttpsError('invalid-argument', 'Unknown app.');
  return tokenFor(role, token.email);
});

exports.switchRole = onCall(options, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const from = roleOf(request);
  if (!VENDOR_APP.includes(from)) throw new HttpsError('permission-denied', 'Switching is only between Vendor and Service provider, in the vendor app.');
  const to = request.data?.to;
  if (!VENDOR_APP.includes(to)) throw new HttpsError('invalid-argument', 'Choose Vendor or Service provider.');
  if (to === from) throw new HttpsError('invalid-argument', 'You are already signed in as that.');
  const email = loginEmail(request);
  if (!email) throw new HttpsError('permission-denied', 'Sign in again.');
  return tokenFor(to, email);
});

module.exports._roleLogins = {roleLoginFor, forgetRoleLogin, tokenFor, loginDocId, claimsFor, emailKey};
module.exports.roleLoginFor = roleLoginFor;
module.exports.forgetRoleLogin = forgetRoleLogin;
module.exports.loginEmailOf = loginEmailOf;
