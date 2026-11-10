'use strict';
// Who is calling. Every app signs in with its OWN login for the role it serves (functions/role-logins.js): one email has a separate
// login, with its own ID, as a customer ('user'), a vendor, a service provider, field staff and (only when set up by
// functions/set-admin.js) the administrator. A role login carries the custom claims {role, loginEmail} (and admin: true on the admin
// login only); it has no email of its own in Firebase Auth, because one email may hold several roles.
//
// The email's own Firebase account (Google, email code or password) only PROVES the email: it has no role, so every check here
// refuses it. It is used for one thing only, asking enterRole for a role login.
const {HttpsError} = require('firebase-functions/v2/https');

const ROLES = ['user', 'vendor', 'provider', 'staff', 'admin'];

/// The role of the signed-in login ('user', 'vendor', 'provider', 'staff' or 'admin'), or '' (not signed in, or the email's own login).
const roleOf = request => {
  const role = request?.auth?.token?.role;
  return ROLES.includes(role) ? role : '';
};

const APP_NAMES = {user: 'the LOCAMARKET app', vendor: 'the vendor app (as a vendor)', provider: 'the vendor app (as a service provider)', staff: 'the staff app', admin: 'the admin panel'};

/// The uid of the signed-in role login. [roles] lists the roles that may call (any role when left out).
function requireRole(request, roles = ROLES) {
  if (!request?.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const role = roleOf(request);
  if (!role) throw new HttpsError('permission-denied', 'Sign in again.');
  if (!roles.includes(role)) {
    throw new HttpsError('permission-denied', `This is available only in ${roles.map(r => APP_NAMES[r]).join(' or ')}.`);
  }
  return request.auth.uid;
}

/// True only for the administrator's own login: the admin claim on a login whose role is 'admin'.
const isAdminToken = token => token?.role === 'admin' && token?.admin === true;

/// The email the signed-in role login belongs to (lower case), or ''.
const loginEmail = request => String(request?.auth?.token?.loginEmail || '');

module.exports = {ROLES, roleOf, requireRole, isAdminToken, loginEmail};
