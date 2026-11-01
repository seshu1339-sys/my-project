'use strict';
// Vendor, service-provider and field-staff accounts are completely separate: one email is only ever one of them. A person who is
// more than one registers each with a different email address. The registrations (registerVendor, registerProvider,
// requestFieldStaffAccess) all ask here before creating anything, and the vendor and staff apps ask again at sign-in (login.js).

const KINDS = ['vendor', 'provider', 'staff'];

/// The one message for every refusal of a second role: the email already holds one of vendor, service provider or staff.
const ROLE_TAKEN = 'This email is already registered in another role. Please use a different email.';

/// Which kinds of account a login already is, from its records (an admin-made Quick Add account counts by its role).
async function accountKinds(db, uid) {
  const [vendorApplication, vendor, quick, providerApplication, provider, staff] = await Promise.all(
    ['vendorApplications', 'vendors', 'quickAccounts', 'providerApplications', 'providers', 'fieldStaff'].map(c => db.collection(c).doc(uid).get()),
  );
  const quickRole = quick.data()?.role;
  return {
    vendor: vendorApplication.exists || vendor.exists || quickRole === 'vendor',
    provider: providerApplication.exists || provider.exists,
    staff: staff.exists || quickRole === 'staff',
  };
}

/// emailRoles/<email> remembers which one of the three roles an email address holds (written the first time it registers as one).
const emailKey = email => String(email || '').trim().toLowerCase();

/// The role an email address already holds ('vendor', 'provider' or 'staff'), or ''.
async function emailRole(db, email) {
  const key = emailKey(email);
  if (!key) return '';
  const role = (await db.collection('emailRoles').doc(key).get()).data()?.role;
  return KINDS.includes(role) ? role : '';
}

/// Records that [email] is [role]. The first role wins: an email that already holds another role is left as it is.
async function claimEmailRole(db, email, role) {
  const key = emailKey(email);
  if (!key || !KINDS.includes(role)) return;
  const ref = db.collection('emailRoles').doc(key);
  await db.runTransaction(async tx => {
    if ((await tx.get(ref)).exists) return;
    tx.set(ref, {role, email: key, createdAt: new Date()});
  });
}

/// Why [uid] / [email] cannot register as [wanted] (vendor, provider or staff) because it already holds another one of the three
/// roles (by the email's record, or by the account's own records), or ''.
async function otherAccountMessage(db, uid, wanted, email) {
  const held = await emailRole(db, email);
  if (held && held !== wanted) return ROLE_TAKEN;
  const kinds = await accountKinds(db, uid);
  return KINDS.some(kind => kind !== wanted && kinds[kind]) ? ROLE_TAKEN : '';
}

module.exports = {accountKinds, otherAccountMessage, ROLE_TAKEN, emailRole, claimEmailRole, emailKey, KINDS};
