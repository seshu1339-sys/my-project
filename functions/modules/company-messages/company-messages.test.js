'use strict';
// Company messages (cost cuts part 5, 18 Nov 2026): one record per message; only the admin or permitted staff send (staff: own vendors,
// never Payment / charges); town + category together; several Vendor IDs; "show until"; edits keep the old words and show "edited"
// with no new push; deletes hide but keep the log; reads counted once; free topic pushes. Emulator only for the writes.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const R = require('./rules');
const S = require('./store');

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const NOW = Date.parse('2026-11-18T10:00:00+05:30');
let seq = 0;
const uniq = name => `${name}${Date.now().toString(36)}${++seq}`;
const ADMIN = {uid: 'admin1', role: 'admin', code: 'owner@locamarket.in'};

test('targets: all, town + category together, Vendor IDs; the push topics match the app\'s', () => {
  assert.deepEqual(R.validateTarget({target: {all: true, towns: ['x']}}), {all: true, towns: [], categories: [], vendorCodes: []});
  const t = R.validateTarget({target: {towns: ['Krishna Bazar (Narsipatnam)'], categories: ['Grocery ']}});
  assert.deepEqual(t, {all: false, towns: ['narsipatnam'], categories: ['grocery'], vendorCodes: []});
  assert.ok(R.matches(t, {town: 'Narsipatnam', category: 'grocery'}));
  assert.ok(!R.matches(t, {town: 'Narsipatnam', category: 'Clothes'}), 'both must fit');
  assert.ok(!R.matches(t, {town: 'Tuni', category: 'Grocery'}));
  assert.throws(() => R.validateTarget({target: {}}), /Choose who gets it/);
  assert.throws(() => R.validateTarget({target: {vendorCodes: ['VEN-1'], towns: ['Tuni']}}), /not both/);
  assert.deepEqual(R.pushPlan('vendors', {all: true, towns: [], categories: []}), [{topic: 'cm_vendors_all'}]);
  assert.deepEqual(R.pushPlan('vendors', t), [{condition: "'cm_vendors_t_narsipatnam' in topics && 'cm_vendors_c_grocery' in topics"}]);
  assert.deepEqual(R.pushPlan('vendors', {all: false, towns: ['tuni'], categories: []}), [{topic: 'cm_vendors_t_tuni'}]);
  assert.deepEqual(R.pushPlan('vendors', t, ['u1', 'u2']), [{topic: 'cm_vendor_u1'}, {topic: 'cm_vendor_u2'}]);
  assert.deepEqual(R.topicsFor('vendors', {uid: 'u1', town: 'Krishna Bazar (Narsipatnam)', category: 'Fancy Store'}),
    ['cm_vendors_all', 'cm_vendors_t_narsipatnam', 'cm_vendors_c_fancy-store', 'cm_vendor_u1']);
});

test('content: Payment / charges needs the old and new amount and the start day, and only the admin sends it', () => {
  assert.throws(() => R.validateContent({type: 'x', title: 'a', body: 'b'}), /message type/);
  assert.throws(() => R.validateContent({type: 'general', title: '', body: 'b'}), /title/);
  assert.throws(() => R.validateContent({type: 'payment', title: 'New fee', body: 'b', newAmount: 200, startsOn: '2026-12-01'}), /old amount/);
  assert.throws(() => R.validateContent({type: 'payment', title: 'New fee', body: 'b', oldAmount: 100, newAmount: 200}), /start/);
  const ok = R.validateContent({type: 'payment', title: 'New fee', body: 'b', oldAmount: '100', newAmount: 199.5, startsOn: '2026-12-01'}, {now: NOW});
  assert.deepEqual([ok.oldAmount, ok.newAmount, ok.startsOn], [100, 199.5, '2026-12-01']);
  assert.throws(() => R.validateContent({type: 'payment', title: 'a', body: 'b', oldAmount: 1, newAmount: 2, startsOn: '2026-12-01'}, {staff: true}), /only from the admin/);
  assert.throws(() => R.validateContent({type: 'general', title: 'a', body: 'b', showUntil: '2026-11-01'}, {now: NOW}), /already passed/);
  assert.equal(R.pushText({type: 'offer', title: 'Diwali offer'}).title, 'LOCAMARKET Team · New offer');
  assert.ok(R.showing({showUntil: '2026-11-18'}, NOW));
  assert.ok(!R.showing({showUntil: '2026-11-17'}, NOW));
  assert.ok(!R.showing({deleted: true}, NOW));
});

async function seedVendors(town, rows) {
  const db = getFirestore();
  const out = [];
  for (const [i, category] of rows.entries()) {
    const uid = uniq('v');
    const code = `VEN-T-${uid.toUpperCase()}`;
    await db.collection('vendors').doc(uid).set({status: 'approved', vendorCode: code, name: `Shop ${i}`});
    await db.collection('shops').doc(uid).set({town, category, name: `Shop ${i}`, ownerId: uid});
    out.push({uid, code});
  }
  await db.collection('companyAudience').doc('vendors').delete(); // counts read the new vendors
  return out;
}
const fakeSend = () => {
  const sent = [];
  return {sent, send: async m => { sent.push(m); return 'id'; }};
};

test('one record per message: town + category reaches only who fits; the everyone-list and the push; reads counted once', emulated, async () => {
  const db = getFirestore();
  const town = uniq('Town');
  const [a, b, c] = await seedVendors(`Ward 2 (${town})`, ['Grocery', 'Grocery', 'Clothes']);
  const push = fakeSend();
  const target = {towns: [town], categories: ['grocery']};
  assert.deepEqual(await S.preview(db, ADMIN, {target}, NOW), {count: 2});
  const r = await S.sendCompanyMessage(db, ADMIN, {type: 'offer', title: 'Diwali', body: 'Free Today\'s Offers box this week', target}, {send: push.send, now: NOW});
  assert.equal(r.meantFor, 2);
  const msg = (await db.collection('companyMessages').doc(r.id).get()).data();
  assert.equal(msg.public, true);
  assert.deepEqual(msg.vendorUids, []);
  assert.deepEqual(msg.sentBy, ADMIN);
  assert.equal(msg.readCount, 0);
  assert.equal(push.sent.length, 1);
  assert.match(push.sent[0].condition, /cm_vendors_t_.* && .*cm_vendors_c_grocery/);
  assert.equal(push.sent[0].notification.title, 'LOCAMARKET Team · New offer');
  assert.deepEqual(push.sent[0].data, {type: 'company_message', id: r.id});
  const index = (await db.collection('companyMessagesIndex').doc('vendors').get()).data().items;
  assert.equal(index[0].id, r.id);
  assert.deepEqual(index[0].towns, [town.toLowerCase()]);
  // Reads: once each; one small record per vendor, no record per message per vendor.
  assert.deepEqual(await S.readCompanyMessages(db, a.uid, {ids: [r.id]}, NOW), {read: 1});
  assert.deepEqual(await S.readCompanyMessages(db, a.uid, {ids: [r.id]}, NOW), {read: 0});
  await S.readCompanyMessages(db, b.uid, {ids: [r.id]}, NOW);
  assert.equal((await db.collection('companyMessages').doc(r.id).get()).data().readCount, 2);
  assert.deepEqual((await db.collection('companyMessageReads').doc(a.uid).get()).data().read, [r.id]);
  assert.ok(c);
});

test('several Vendor IDs: only they can read it, each gets their own push; an unknown ID is refused', emulated, async () => {
  const db = getFirestore();
  const [a, b, other] = await seedVendors(uniq('Town'), ['Fancy', 'Fancy', 'Fancy']);
  const push = fakeSend();
  await assert.rejects(S.sendCompanyMessage(db, ADMIN, {type: 'account', title: 'Reset', body: 'x', target: {vendorCodes: ['VEN-NOBODY']}}, {send: push.send, now: NOW}), /No vendor has the ID VEN-NOBODY/);
  const r = await S.sendCompanyMessage(db, ADMIN, {type: 'account', title: 'Your login was reset', body: 'Sign in again with Google.', target: {vendorCodes: [a.code, b.code.toLowerCase()]}}, {send: push.send, now: NOW});
  const msg = (await db.collection('companyMessages').doc(r.id).get()).data();
  assert.equal(msg.public, false);
  assert.deepEqual(msg.vendorUids.sort(), [a.uid, b.uid].sort());
  assert.deepEqual(push.sent.map(p => p.topic).sort(), [`cm_vendor_${a.uid.toLowerCase()}`, `cm_vendor_${b.uid.toLowerCase()}`].sort());
  const index = (await db.collection('companyMessagesIndex').doc('vendors').get()).data()?.items || [];
  assert.equal(index.some(e => e.id === r.id), false, 'a private message is never in the everyone-list');
  assert.deepEqual(await S.readCompanyMessages(db, other.uid, {ids: [r.id]}, NOW), {read: 0}, 'not theirs: not counted');
});

test('edit keeps the old words and shows "edited" with no push; delete hides it but keeps the log', emulated, async () => {
  const db = getFirestore();
  const town = uniq('Town');
  await seedVendors(town, ['Kirana']);
  const push = fakeSend();
  const {id} = await S.sendCompanyMessage(db, ADMIN, {type: 'payment', title: 'New plan price', body: 'Silver changes', oldAmount: 499, newAmount: 599, startsOn: '2026-12-01', target: {towns: [town]}}, {send: push.send, now: NOW});
  const pushes = push.sent.length;
  await S.editCompanyMessage(db, ADMIN, {id, title: 'New Silver price', body: 'Silver changes on 1 Dec', oldAmount: 499, newAmount: 549, startsOn: '2026-12-01'}, NOW + 60000);
  let msg = (await db.collection('companyMessages').doc(id).get()).data();
  assert.equal(msg.edited, true);
  assert.equal(msg.title, 'New Silver price');
  assert.equal(msg.newAmount, 549);
  assert.equal(msg.versions.length, 1);
  assert.deepEqual([msg.versions[0].title, msg.versions[0].newAmount], ['New plan price', 599]);
  assert.equal(push.sent.length, pushes, 'no new push for an edit');
  let entry = (await db.collection('companyMessagesIndex').doc('vendors').get()).data().items.find(e => e.id === id);
  assert.deepEqual([entry.edited, entry.newAmount], [true, 549]);
  await S.deleteCompanyMessage(db, ADMIN, {id}, NOW + 120000);
  msg = (await db.collection('companyMessages').doc(id).get()).data();
  assert.equal(msg.deleted, true, 'kept in the log');
  entry = (await db.collection('companyMessagesIndex').doc('vendors').get()).data().items.find(e => e.id === id);
  assert.equal(entry, undefined, 'hidden from vendors');
  await assert.rejects(S.editCompanyMessage(db, ADMIN, {id, title: 'x', body: 'y'}, NOW), /deleted/);
});

test('staff: only when the admin allowed them, only to their own vendors, never Payment / charges', emulated, async () => {
  const db = getFirestore();
  const staffUid = uniq('s');
  const code = `STF-${staffUid.toUpperCase()}`;
  await db.collection('fieldStaff').doc(staffUid).set({status: 'active', staffCode: code, name: 'Ravi'});
  const auth = {uid: staffUid, token: {role: 'staff'}};
  await assert.rejects(S.senderOf(db, auth, {isAdmin: false}), /not allowed you/);
  await S.saveSenders(db, {staffCodes: [code.toLowerCase()]});
  await assert.rejects(S.saveSenders(db, {staffCodes: ['STF-NOBODY']}), /No staff member/);
  await S.saveSenders(db, {staffCodes: [code]});
  const sender = await S.senderOf(db, auth, {isAdmin: false});
  assert.deepEqual(sender, {uid: staffUid, role: 'staff', code});
  await assert.rejects(S.senderOf(db, {uid: 'v9', token: {role: 'vendor'}}, {isAdmin: false}), /Only the admin or permitted staff/);
  const town = uniq('Town');
  const [mine, notMine] = await seedVendors(town, ['Grocery', 'Grocery']);
  await db.collection('staffLinks').doc(`vendor_${mine.uid}`).set({kind: 'vendor', accountUid: mine.uid, staffUid});
  await assert.rejects(S.sendCompanyMessage(db, sender, {type: 'payment', title: 'a', body: 'b', oldAmount: 1, newAmount: 2, startsOn: '2026-12-01', target: {all: true}}, {now: NOW}), /only from the admin/);
  await assert.rejects(S.sendCompanyMessage(db, sender, {type: 'general', title: 'a', body: 'b', target: {vendorCodes: [notMine.code]}}, {now: NOW}), /own area/);
  const push = fakeSend();
  const r = await S.sendCompanyMessage(db, sender, {type: 'general', title: 'Market closed Sunday', body: 'b', target: {towns: [town]}}, {send: push.send, now: NOW});
  assert.equal(r.meantFor, 1, 'only their own vendor in that town');
  const msg = (await db.collection('companyMessages').doc(r.id).get()).data();
  assert.deepEqual(msg.vendorUids, [mine.uid], 'sent to their vendors by name, never to the whole town');
  assert.deepEqual(push.sent.map(p => p.topic), [`cm_vendor_${mine.uid.toLowerCase()}`]);
  await assert.rejects(S.editCompanyMessage(db, {uid: 'other', role: 'staff', code: 'X'}, {id: r.id, title: 'x', body: 'y'}, NOW), /not found/);
  await db.collection('companyMessageSenders').doc('main').delete();
});
