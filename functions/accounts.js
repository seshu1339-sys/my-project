'use strict';
// What kind of account a login is, from its own records. One email may hold every role, each with its own login and ID
// (functions/role-logins.js), so a login's records only ever belong to that one role.

const KINDS = ['vendor', 'provider', 'staff'];

/// Which kinds of account a login is, from its records (an admin-made Quick Add account counts by its role).
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

module.exports = {accountKinds, KINDS};
