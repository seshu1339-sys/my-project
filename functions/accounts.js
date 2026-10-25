'use strict';
// Vendor, service-provider and field-staff accounts are completely separate: one login is only ever one of them. A person who is
// more than one registers each with a different email address. The registrations (registerVendor, registerProvider,
// requestFieldStaffAccess) all ask here before creating anything.

const KINDS = ['vendor', 'provider', 'staff'];
const TAKEN = {
  vendor: 'This account is a vendor account.',
  provider: 'This account is a service-provider account.',
  staff: 'This account is a field-staff account.',
};
const AS = {vendor: 'a vendor', provider: 'a service provider', staff: 'field staff'};

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

/// Why [uid] cannot register as [wanted] (vendor, provider or staff) because it is already another kind of account, or ''.
async function otherAccountMessage(db, uid, wanted) {
  const kinds = await accountKinds(db, uid);
  const other = KINDS.find(kind => kind !== wanted && kinds[kind]);
  return other ? `${TAKEN[other]} Register as ${AS[wanted]} with a different email address.` : '';
}

module.exports = {accountKinds, otherAccountMessage};
