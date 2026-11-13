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

// ---- The admin links at any time; the vendor asks for local staff (owner, 13 Nov 2026) ----
//   staffLinkRequests/<kind>_<uid>  {kind, accountUid, code, name, town, phone, latitude, longitude, status: 'open' | 'linked', at}

/// The registration of a vendor or provider by their ID or uid: {kind, ref, app, code}.
async function registration(db, data) {
  const parsed = parseCode(data.code);
  if (parsed) {
    const [collection, field] = APPLICATIONS[parsed.kind];
    const found = await db.collection(collection).where(field, '==', parsed.code).limit(1).get();
    if (found.empty) throw Error(`No registration has the ID ${parsed.code}.`);
    return {kind: parsed.kind, ref: found.docs[0].ref, app: found.docs[0].data(), code: parsed.code};
  }
  const kind = data.kind === 'provider' ? 'provider' : data.kind === 'vendor' ? 'vendor' : null;
  if (!kind || typeof data.accountUid !== 'string' || !ID.test(data.accountUid)) throw Error('Enter the Vendor ID or the service provider ID.');
  const [collection, field] = APPLICATIONS[kind];
  const doc = await db.collection(collection).doc(data.accountUid).get();
  if (!doc.exists) throw Error('That registration was not found.');
  return {kind, ref: doc.ref, app: doc.data(), code: doc.data()[field] || ''};
}

/// The active staff whose own area holds this point (only they may be linked to the person).
async function staffInAreaOf(db, place) {
  const holders = await db.collection('staffAreaHolders').get();
  const out = [];
  for (const holder of holders.docs) {
    const staffUid = holder.data().staffUid;
    if (!staffUid) continue;
    const [area, staff] = await Promise.all([db.collection('staffAreas').doc(holder.id).get(), db.collection('fieldStaff').doc(staffUid).get()]);
    if (!area.exists || staff.data()?.status !== 'active') continue;
    if (areaProblem({id: area.id, ...area.data()}, place)) continue;
    out.push({staffUid, staffCode: staff.data().staffCode || '', name: staff.data().name || '', phone: staff.data().phone || '', areaName: area.data().name || ''});
  }
  return out;
}

/// The admin links a vendor or provider to a staff member at any time (no 30-minute limit), only when the person is inside the staff
/// member's own area. An existing link is replaced. An open request of the person is closed.
async function adminLink(db, adminUid, data = {}, now = Date.now()) {
  const {kind, ref, app, code} = await registration(db, data);
  if (typeof data.staffUid !== 'string' || !ID.test(data.staffUid)) throw Error('Choose the staff member.');
  const staff = await activeStaff(db, data.staffUid);
  const area = await ownArea(db, data.staffUid);
  if (!area) throw Error('This staff member has no area yet, so nobody can be linked to them.');
  if (areaProblem(area, app)) throw Error(`This vendor or provider is outside the area "${area.name}" of ${staff.staffCode || 'this staff member'}, so they cannot be linked.`);
  const at = Timestamp.fromMillis(now);
  const link = {
    kind, accountUid: ref.id, code, name: app.name || '', town: app.town || '', pincode: app.pincode || '',
    staffUid: data.staffUid, staffCode: staff.staffCode || '', staffName: staff.name || '',
    registeredAt: app.submittedAt ?? at, linkedAt: at, linkedBy: 'admin', linkedByUid: adminUid,
  };
  const batch = db.batch();
  batch.set(db.collection('staffLinks').doc(linkId(kind, ref.id)), link);
  batch.set(ref, {registeredByStaffUid: data.staffUid, registeredByStaffCode: staff.staffCode || '', registeredByLinkedAt: at}, {merge: true});
  batch.set(db.collection('staffLinkRequests').doc(`${kind}_${ref.id}`), {status: 'linked', staffUid: data.staffUid, staffCode: staff.staffCode || '', decidedAt: at}, {merge: true});
  await batch.commit();
  return {linkId: linkId(kind, ref.id), staffCode: staff.staffCode || ''};
}

/// A vendor or provider asks (from the Support Team chat) to be connected to the staff of their area. No staff ID is needed: the admin
/// chooses from the staff of that area. One open request at a time.
async function requestLocalStaff(db, uid, role, now = Date.now()) {
  const kind = role === 'provider' ? 'provider' : 'vendor';
  const [collection, field] = APPLICATIONS[kind];
  const app = (await db.collection(collection).doc(uid).get()).data();
  if (!app) throw Error('Register your shop or service first, then ask for local staff.');
  if ((await db.collection('staffLinks').doc(linkId(kind, uid)).get()).exists) throw Error('You are already connected to a staff member of your area.');
  const ref = db.collection('staffLinkRequests').doc(`${kind}_${uid}`);
  const current = (await ref.get()).data();
  if (current?.status === 'open') return {status: 'open', already: true};
  await ref.set({
    kind, accountUid: uid, code: app[field] || '', name: app.name || '', town: app.town || '', phone: app.phone || '',
    latitude: app.latitude ?? null, longitude: app.longitude ?? null, status: 'open', at: Timestamp.fromMillis(now),
  });
  return {status: 'open'};
}

module.exports = {linkAccount, removeLink, disableOldStaffAdded, OLD_REASON, adminLink, requestLocalStaff, staffInAreaOf, registration};
