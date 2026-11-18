'use strict';
// Company messages: what this module reads and writes (owner, 18 Nov 2026: cost cuts part 5). ONE record per message, never one per
// vendor; read status is one small record per vendor.
//
//   companyMessages/<id>             {audience, type, title, body, hasPhoto, oldAmount?, newAmount?, startsOn?, target: {all, towns,
//                                     categories, vendorCodes}, public, vendorUids, showUntil, sentBy: {uid, role, code}, sentAt, meantFor,
//                                     pushes, readCount, edited, editedAt, versions: [the earlier words, each with editedAt / editedBy],
//                                     deleted, deletedAt, deletedBy}            the message AND its log line (who, when, to whom, how many)
//   companyMessagePhotos/<id>        {data (JPEG / PNG base64, at most 80 KB), type}   the optional photo (Firestore: free reads)
//   companyMessagesIndex/<audience>  {items: [the newest INDEX_SIZE messages sent to all / towns / categories]}: the app reads this ONE
//                                     record to find what is for it; messages to chosen Vendor IDs are read with a query (vendorUids)
//   companyMessageReads/<uid>        {read: [message ids], at}  which messages this vendor opened (one record per vendor)
//   companyMessageSenders/main       {staff: [{uid, code, name}]}   the staff the admin allowed to send (only to their own vendors,
//                                     never Payment / charges)
//   companyAudience/<audience>       {at, people: [{u, t, c, v, n}]}   every vendor's uid, town, category, Vendor ID and name, rebuilt at
//                                     most once an hour: the counts ("this will go to N vendors") cost one read
// Staff "own area" = the vendors linked to them (staffLinks, Staff Links module: a link is only possible inside the staff member's area).
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {TYPES, INDEX_SIZE, MAX_PEOPLE, townKey, categoryKey, pushPlan, matches, validateContent, validateTarget, pushText, showing, indexEntry} = require('./rules');

const AUDIENCE = 'vendors';
const AUDIENCE_TTL = 3600000;
const MAX_PHOTO = 80 * 1024;
const MAX_READ_IDS = 300;

const messages = db => db.collection('companyMessages');
const indexRef = db => db.collection('companyMessagesIndex').doc(AUDIENCE);
const sendersRef = db => db.collection('companyMessageSenders').doc('main');

/// Who is sending: the admin (any message), or a staff member the admin allowed (their own vendors, no Payment / charges).
async function senderOf(db, auth, {isAdmin}) {
  if (isAdmin) return {uid: auth.uid, role: 'admin', code: String(auth.token?.email || 'admin')};
  if (auth?.token?.role !== 'staff') throw Error('Only the admin or permitted staff can send company messages.');
  const allowed = ((await sendersRef(db).get()).data()?.staff || []).some(s => s.uid === auth.uid);
  const staff = (await db.collection('fieldStaff').doc(auth.uid).get()).data();
  if (!allowed || staff?.status !== 'active') throw Error('The admin has not allowed you to send company messages.');
  return {uid: auth.uid, role: 'staff', code: String(staff.staffCode || staff.code || '')};
}

/// Every vendor with their town and category (from their shop), cached for an hour in one record.
async function audience(db, now = Date.now(), {fresh = false} = {}) {
  const ref = db.collection('companyAudience').doc(AUDIENCE);
  const cached = (await ref.get()).data();
  if (!fresh && cached && now - (cached.at?.toMillis?.() ?? 0) < AUDIENCE_TTL) return cached.people || [];
  const vendors = await db.collection('vendors').select('vendorCode', 'status', 'name').get();
  const shops = new Map((await db.collection('shops').select('town', 'category', 'ownerId', 'name').get()).docs.map(d => [d.id, d.data()]));
  const people = [];
  for (const v of vendors.docs) {
    const d = v.data();
    if (d.status && !['approved', 'active'].includes(d.status)) continue;
    const shop = shops.get(v.id) || {};
    people.push({u: v.id, t: townKey(shop.town), c: categoryKey(shop.category), v: String(d.vendorCode || ''), n: String(shop.name || d.name || '').slice(0, 60)});
  }
  await ref.set({at: Timestamp.fromMillis(now), people});
  return people;
}

/// The staff member's own vendors (linked to them).
async function staffVendorUids(db, staffUid) {
  const q = await db.collection('staffLinks').where('staffUid', '==', staffUid).get();
  return new Set(q.docs.filter(d => d.data().kind === 'vendor').map(d => d.data().accountUid));
}

/// Who a message goes to: [uids] when it is for chosen people (Vendor IDs, or a staff member's vendors), else [] (everyone it fits).
async function recipients(db, sender, target, now) {
  const people = await audience(db, now);
  let chosen = null;
  if (target.vendorCodes.length) {
    const byCode = new Map(people.map(p => [p.v.toUpperCase(), p.u]));
    const missing = target.vendorCodes.filter(c => !byCode.has(c));
    if (missing.length) throw Error(`No vendor has the ID ${missing.slice(0, 5).join(', ')}.`);
    chosen = target.vendorCodes.map(c => byCode.get(c));
  }
  if (sender.role === 'staff') {
    const mine = await staffVendorUids(db, sender.uid);
    const fit = people.filter(p => mine.has(p.u) && (chosen ? chosen.includes(p.u) : matches(target, {uid: p.u, town: p.t, category: p.c})));
    if (chosen && fit.length < chosen.length) throw Error('You can send only to the vendors of your own area.');
    return {uids: fit.map(p => p.u), count: fit.length, direct: true};
  }
  if (chosen) return {uids: chosen, count: chosen.length, direct: true};
  const count = people.filter(p => matches(target, {uid: p.u, town: p.t, category: p.c})).length;
  return {uids: [], count, direct: false};
}

/// "This will go to N vendors" before Send.
async function preview(db, sender, data = {}, now = Date.now()) {
  const target = validateTarget(data);
  const {count} = await recipients(db, sender, target, now);
  return {count};
}

function photoOf(base64) {
  if (!base64) return null;
  const bytes = typeof base64 === 'string' ? Buffer.from(base64, 'base64') : null;
  const jpeg = bytes && bytes[0] === 0xff && bytes[1] === 0xd8, png = bytes && bytes[0] === 0x89 && bytes[1] === 0x50;
  if (!bytes || bytes.length > MAX_PHOTO || (!jpeg && !png)) throw Error(`The photo must be a JPEG or PNG under ${MAX_PHOTO / 1024} KB.`);
  return {data: base64, type: jpeg ? 'image/jpeg' : 'image/png'};
}

/// Puts one message into the everyone-list, or takes it out ([msg] null), keeping the newest INDEX_SIZE still showing.
async function updateIndex(db, id, msg, now) {
  await db.runTransaction(async tx => {
    const items = ((await tx.get(indexRef(db))).data()?.items || []).filter(e => e.id !== id);
    if (msg) items.unshift(indexEntry(id, msg));
    const keep = items.filter(e => showing(e, now)).sort((a, b) => (b.sentAt?.toMillis?.() ?? 0) - (a.sentAt?.toMillis?.() ?? 0)).slice(0, INDEX_SIZE);
    tx.set(indexRef(db), {items: keep, updatedAt: Timestamp.fromMillis(now)});
  });
}

/// The free push (Firebase Cloud Messaging topics): never throws; returns how many pushes went out.
async function push(send, plan, msg, id) {
  const {title, body} = pushText(msg);
  let sent = 0;
  for (const p of plan) {
    try {
      await send({...p, notification: {title, body}, data: {type: 'company_message', id}, android: {priority: 'high'}});
      sent++;
    } catch (error) {
      console.warn('Company message push failed', error.code || error.message);
    }
  }
  return sent;
}

/// Sends one message: one record, the photo, the everyone-list, and the push.
async function sendCompanyMessage(db, sender, data = {}, {send, now = Date.now()} = {}) {
  const content = validateContent(data, {staff: sender.role === 'staff', now});
  const target = validateTarget(data);
  const photo = photoOf(data.photo);
  const {uids, count, direct} = await recipients(db, sender, target, now);
  if (!count) throw Error('No vendor fits this choice yet.');
  if (uids.length > MAX_PEOPLE) throw Error(`A message to chosen vendors can go to at most ${MAX_PEOPLE}. Choose a town or a category instead.`);
  const ref = messages(db).doc();
  const at = Timestamp.fromMillis(now);
  const msg = {
    audience: AUDIENCE, ...content, hasPhoto: !!photo, target, public: !direct, vendorUids: direct ? uids : [],
    sentBy: sender, sentAt: at, meantFor: count, pushes: 0, readCount: 0, edited: false, deleted: false, versions: [],
  };
  const batch = db.batch();
  batch.set(ref, msg);
  if (photo) batch.set(db.collection('companyMessagePhotos').doc(ref.id), photo);
  await batch.commit();
  if (!direct) await updateIndex(db, ref.id, msg, now);
  const pushes = send ? await push(send, pushPlan(AUDIENCE, target, direct ? uids : []), msg, ref.id) : 0;
  await ref.update({pushes});
  return {id: ref.id, meantFor: count, pushes};
}

/// The admin, or the staff member who sent it, may change or delete it.
async function ownMessage(db, sender, id) {
  if (typeof id !== 'string' || !/^[A-Za-z0-9]{1,40}$/.test(id)) throw Error('That message was not found.');
  const ref = messages(db).doc(id);
  const msg = (await ref.get()).data();
  if (!msg || (sender.role !== 'admin' && msg.sentBy?.uid !== sender.uid)) throw Error('That message was not found.');
  return {ref, msg};
}

/// A change after sending: the vendor sees "edited"; the earlier words stay in `versions` for the admin. No new push (owner).
async function editCompanyMessage(db, sender, data = {}, now = Date.now()) {
  const {ref, msg} = await ownMessage(db, sender, data.id);
  if (msg.deleted) throw Error('A deleted message cannot be changed.');
  const content = validateContent({...data, type: msg.type}, {staff: sender.role === 'staff', now});
  const at = Timestamp.fromMillis(now);
  const before = {title: msg.title, body: msg.body, showUntil: msg.showUntil || '', ...(msg.type === 'payment' ? {oldAmount: msg.oldAmount, newAmount: msg.newAmount, startsOn: msg.startsOn} : {})};
  const changes = {...content, edited: true, editedAt: at, editedBy: sender, versions: FieldValue.arrayUnion({...before, replacedAt: at, replacedBy: sender.code})};
  await ref.update(changes);
  if (msg.public) await updateIndex(db, ref.id, {...msg, ...content, edited: true, editedAt: at}, now);
  return {edited: true};
}

/// Deleting hides it from vendors; the record stays in the admin's log, marked deleted.
async function deleteCompanyMessage(db, sender, data = {}, now = Date.now()) {
  const {ref, msg} = await ownMessage(db, sender, data.id);
  if (msg.deleted) return {deleted: true};
  await ref.update({deleted: true, deletedAt: Timestamp.fromMillis(now), deletedBy: sender});
  if (msg.public) await updateIndex(db, ref.id, null, now);
  return {deleted: true};
}

/// A vendor opened their inbox: these messages count as read (once each), in their one read record.
async function readCompanyMessages(db, uid, data = {}, now = Date.now()) {
  const ids = [...new Set((Array.isArray(data.ids) ? data.ids : []).filter(id => typeof id === 'string' && /^[A-Za-z0-9]{1,40}$/.test(id)))].slice(0, 50);
  if (!ids.length) return {read: 0};
  const readRef = db.collection('companyMessageReads').doc(uid);
  return db.runTransaction(async tx => {
    const had = (await tx.get(readRef)).data()?.read || [];
    const fresh = ids.filter(id => !had.includes(id));
    const docs = fresh.length ? await tx.getAll(...fresh.map(id => messages(db).doc(id))) : [];
    const counted = [];
    for (const d of docs) {
      const m = d.data();
      if (!m || m.deleted || (!m.public && !(m.vendorUids || []).includes(uid))) continue;
      tx.update(d.ref, {readCount: FieldValue.increment(1)});
      counted.push(d.id);
    }
    if (counted.length) tx.set(readRef, {read: [...had, ...counted].slice(-MAX_READ_IDS), at: Timestamp.fromMillis(now)});
    return {read: counted.length};
  });
}

/// The admin chooses which staff may send (by Staff ID).
async function saveSenders(db, data = {}) {
  const codes = [...new Set((Array.isArray(data.staffCodes) ? data.staffCodes : []).map(c => String(c || '').trim().toUpperCase()).filter(Boolean))].slice(0, 200);
  const staff = [];
  for (let i = 0; i < codes.length; i += 30) {
    const q = await db.collection('fieldStaff').where('staffCode', 'in', codes.slice(i, i + 30)).get();
    for (const d of q.docs) staff.push({uid: d.id, code: String(d.data().staffCode || ''), name: String(d.data().name || '').slice(0, 60)});
  }
  const missing = codes.filter(c => !staff.some(s => s.code.toUpperCase() === c));
  if (missing.length) throw Error(`No staff member has the ID ${missing.slice(0, 5).join(', ')}.`);
  await sendersRef(db).set({staff, updatedAt: FieldValue.serverTimestamp()});
  return {staff};
}

module.exports = {TYPES, AUDIENCE, senderOf, audience, preview, sendCompanyMessage, editCompanyMessage, deleteCompanyMessage, readCompanyMessages, saveSenders, recipients, staffVendorUids};
