'use strict';
// Staff links: what this module reads and writes.
//   staffLinks/<kind>_<uid>    one link: {kind: 'vendor' | 'provider', accountUid, code, name, town, staffUid, staffCode, staffName,
//                              registeredAt, linkedAt}. Read by the staff member (their own), the admin, and the person themself.
//   vendorApplications/<uid>   read (vendorCode, submittedAt, status); the link adds registeredByStaffUid / registeredByStaffCode
//   providerApplications/<uid> the same for providers (providerCode)
//   fieldStaff/<uid>           read: only an active staff member links, with their Staff ID
//   staffAreaStaff, staffAreas, staffAreaHolders   read (the Staff Area System's records): only registrations inside the staff
//                              member's own area can be linked
// Old way (closed): vendors and providers that staff created themselves (vendors/providers with noLogin + addedByStaffUid) are
// disabled by the admin's one button (disableOldStaffAdded) and must register themselves and be linked again.
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {parseCode, linkProblem, timeLeftText, linkId, areaProblem} = require('./rules');

const APPLICATIONS = {vendor: ['vendorApplications', 'vendorCode'], provider: ['providerApplications', 'providerCode']};
const ID = /^[a-zA-Z0-9_-]{1,128}$/;

async function activeStaff(db, staffUid) {
  const staff = (await db.collection('fieldStaff').doc(staffUid).get()).data();
  if (staff?.status !== 'active') throw Error('Only approved staff can link vendors.');
  return staff;
}

/// The staff member's own area (booked or held for them), or null.
async function ownArea(db, staffUid) {
  const mine = (await db.collection('staffAreaStaff').doc(staffUid).get()).data();
  if (!mine?.areaId) return null;
  const [area, holder] = await Promise.all([db.collection('staffAreas').doc(mine.areaId).get(), db.collection('staffAreaHolders').doc(mine.areaId).get()]);
  if (!area.exists || holder.data()?.staffUid !== staffUid) return null;
  return {id: area.id, ...area.data()};
}

/// A staff member links the vendor or provider with this ID, within 30 minutes of their registration, if it is inside their area.
async function linkAccount(db, staffUid, data = {}, now = Date.now()) {
  const staff = await activeStaff(db, staffUid);
  const parsed = parseCode(data.code);
  if (!parsed) throw Error('Enter the ID as it is in the vendor app, like VEN-NRPM-116-325 or SRV-NRPM-116-001.');
  const [collection, field] = APPLICATIONS[parsed.kind];
  const found = await db.collection(collection).where(field, '==', parsed.code).limit(1).get();
  if (found.empty) throw Error(`No registration has the ID ${parsed.code}.`);
  const application = found.docs[0];
  const app = application.data();
  if (app.status === 'rejected') throw Error('This registration was not approved, so it cannot be linked.');
  const registeredAt = app.submittedAt?.toMillis?.() ?? 0;
  const area = await ownArea(db, staffUid);
  const outside = areaProblem(area, app);
  if (outside) throw Error(outside);
  const problem = linkProblem(registeredAt, now);
  const ref = db.collection('staffLinks').doc(linkId(parsed.kind, application.id));
  return db.runTransaction(async tx => {
    const existing = (await tx.get(ref)).data();
    if (existing) throw Error(existing.staffUid === staffUid ? 'You already linked this registration.' : `This registration is already linked to ${existing.staffCode || 'another staff member'}.`);
    if (problem) throw Error(problem);
    const at = Timestamp.fromMillis(now);
    const link = {
      kind: parsed.kind, accountUid: application.id, code: parsed.code, name: app.name || '', town: app.town || '', pincode: app.pincode || '',
      staffUid, staffCode: staff.staffCode || '', staffName: staff.name || '', registeredAt: Timestamp.fromMillis(registeredAt), linkedAt: at,
    };
    tx.create(ref, link);
    tx.set(application.ref, {registeredByStaffUid: staffUid, registeredByStaffCode: staff.staffCode || '', registeredByLinkedAt: at}, {merge: true});
    return {linkId: ref.id, kind: parsed.kind, name: link.name, code: parsed.code, linkedWithin: timeLeftText(registeredAt, now)};
  });
}

/// The admin removes a wrong link (for example the wrong ID was typed). The person stays as they are.
async function removeLink(db, data = {}) {
  if (typeof data.linkId !== 'string' || !ID.test(data.linkId)) throw Error('Choose a link.');
  const ref = db.collection('staffLinks').doc(data.linkId);
  const link = (await ref.get()).data();
  if (!link) throw Error('That link was not found.');
  const [collection] = APPLICATIONS[link.kind] || [];
  const batch = db.batch();
  batch.delete(ref);
  if (collection) batch.set(db.collection(collection).doc(link.accountUid), {registeredByStaffUid: FieldValue.delete(), registeredByStaffCode: FieldValue.delete(), registeredByLinkedAt: FieldValue.delete()}, {merge: true});
  await batch.commit();
  return {removed: true};
}

/// Hides what an old staff-created vendor or provider shows customers, and marks it, so the admin's choice can be told apart later.
async function hideOwned(db, collection, ownerId) {
  const found = await db.collection(collection).where('ownerId', '==', ownerId).get();
  let changed = 0;
  for (let i = 0; i < found.docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of found.docs.slice(i, i + 400)) {
      if (doc.data().active === false) continue;
      batch.update(doc.ref, {active: false, hiddenBySuspension: ownerId, hiddenReason: 'oldStaffAdded'});
      changed++;
    }
    await batch.commit();
  }
  return changed;
}

const OLD_REASON = 'Added by staff the old way. The vendor now registers in the vendor app, and staff link them with their ID.';

/// The admin's one button: every vendor and provider that staff created themselves (no login of their own) is suspended and hidden,
/// and every old staff addition still waiting is closed. Safe to press again.
async function disableOldStaffAdded(db, adminUid, now = Date.now()) {
  const at = Timestamp.fromMillis(now);
  const counts = {vendors: 0, providers: 0, items: 0, waitingClosed: 0};
  const vendors = await db.collection('vendors').where('noLogin', '==', true).get();
  for (const doc of vendors.docs) {
    const vendor = doc.data();
    if (!vendor.addedByStaffUid || vendor.status !== 'approved') continue;
    await doc.ref.update({status: 'suspended', suspensionReason: OLD_REASON, suspendedAt: at, suspendedBy: adminUid, oldStaffAdded: true});
    counts.vendors++;
    counts.items += await hideOwned(db, 'products', doc.id) + await hideOwned(db, 'shops', doc.id);
  }
  const providers = await db.collection('providers').where('noLogin', '==', true).get();
  for (const doc of providers.docs) {
    const provider = doc.data();
    if (!provider.addedByStaffUid || provider.status !== 'approved') continue;
    await doc.ref.update({status: 'suspended', suspensionReason: OLD_REASON, suspendedAt: at, suspendedBy: adminUid, oldStaffAdded: true});
    counts.providers++;
    counts.items += await hideOwned(db, 'services', doc.id);
  }
  const waiting = await db.collection('staffAdditions').where('status', '==', 'pending').get();
  for (const doc of waiting.docs) {
    await doc.ref.update({status: 'closed', decisionReason: OLD_REASON, decidedAt: at, decidedBy: adminUid});
    counts.waitingClosed++;
  }
  return counts;
}

module.exports = {linkAccount, removeLink, disableOldStaffAdded, OLD_REASON};
