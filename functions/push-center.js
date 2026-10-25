'use strict';
// The admin's push notification centre (Admin > Insights > Analytics > Push notifications):
//   sendPushNotification  admin -> a notification to everyone with notifications on, to one town, or to one person; each send is a
//                          pushLog/<nid> record (who it went to, how many devices got it) with pushLog/<nid>/recipients/<uid>
//   trackPushOpen         app   -> a notification was opened (the nid of an admin send, or the type of an automatic one)
//   pushAudience          admin -> how many have notifications on and how many turned them off, by town
//   pushNotOpened         admin -> who got a notification and has not opened it (email and name)
// Automatic notifications (notifications.js) are counted per type and day in pushTypeDaily/<type>~<day> (sent there, opened here).
// Cost guards: at most MAX_RECIPIENTS people per send, and only people who turned notifications on (their choice is respected).
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {getAuth} = require('firebase-admin/auth');
const {requireAdminSession} = require('./admin-session');
const {placeForPincode} = require('./places');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 5, invoker: 'public'};

const MAX_RECIPIENTS = 5000;
const dayKey = (now = Date.now()) => new Date(now + 19800000).toISOString().slice(0, 10);
/// "Krishna Bazar (Narsipatnam)" is in Narsipatnam (lib/domain/towns.dart townKey).
const townKey = town => {
  const bracket = String(town || '').match(/\(([^)]+)\)/);
  return String(bracket ? bracket[1] : town || '').trim().toLowerCase().replace(/\s+/g, ' ');
};

async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true || request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
}

async function* subscribers(query) {
  let cursor;
  do {
    const page = await (cursor ? query.startAfter(cursor) : query).limit(300).get();
    for (const doc of page.docs) yield doc;
    cursor = page.size === 300 ? page.docs.at(-1) : null;
  } while (cursor);
}

/// The people a notification goes to: everyone with notifications on, those in [town], or the one [uid].
async function recipients({audience, town, uid}) {
  if (audience === 'person') {
    const sub = (await db.collection('notificationSubscribers').doc(uid).get()).data();
    return {uids: sub?.enabled ? [uid] : [], off: sub?.enabled ? 0 : 1};
  }
  const uids = [];
  const wanted = townKey(town);
  for await (const doc of subscribers(db.collection('notificationSubscribers').where('enabled', '==', true).orderBy('__name__'))) {
    if (audience === 'town' && townKey(placeForPincode(String(doc.data().pincode || ''))?.town) !== wanted) continue;
    uids.push(doc.id);
    if (uids.length >= MAX_RECIPIENTS) break;
  }
  return {uids, off: 0};
}

/// Sends to one person's devices; how many devices got it.
async function deliverTo(uid, notification, data, link) {
  const tokens = await db.collection('users').doc(uid).collection('pushTokens').get();
  if (tokens.empty) return {status: 'no-token', devices: 0};
  if (process.env.PUSH_DRY_RUN === 'true') {
    await db.collection('_pushDryRun').add({uid, notification, data, tokenCount: tokens.size, createdAt: FieldValue.serverTimestamp()});
    return {status: 'sent', devices: tokens.size};
  }
  let devices = 0;
  for (let i = 0; i < tokens.size; i += 500) {
    const batch = tokens.docs.slice(i, i + 500);
    const result = await getMessaging().sendEachForMulticast({
      tokens: batch.map(d => d.data().token), notification, data,
      webpush: {fcmOptions: {link}}, android: {priority: 'high'}, apns: {payload: {aps: {sound: 'default'}}},
    });
    devices += result.successCount;
    for (let j = 0; j < result.responses.length; j++) {
      const code = result.responses[j].error?.code;
      if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code)) await batch[j].ref.delete();
    }
  }
  return {status: devices ? 'sent' : 'failed', devices};
}

function message(data = {}) {
  const title = typeof data.title === 'string' ? data.title.trim() : '';
  const body = typeof data.body === 'string' ? data.body.trim() : '';
  if (title.length < 2 || title.length > 80) throw Error('Write a title (2-80 characters).');
  if (body.length < 2 || body.length > 300) throw Error('Write the message (2-300 characters).');
  const audience = ['all', 'town', 'person'].includes(data.audience) ? data.audience : '';
  if (!audience) throw Error('Choose who gets it.');
  const town = typeof data.town === 'string' ? data.town.trim().slice(0, 60) : '';
  if (audience === 'town' && !town) throw Error('Choose the town.');
  const person = typeof data.person === 'string' ? data.person.trim() : '';
  if (audience === 'person' && !person) throw Error('Give the person\'s email or account id.');
  return {title, body, audience, town, person};
}

exports.sendPushNotification = onCall({...options, timeoutSeconds: 540}, async request => {
  await requireAdmin(request);
  let m;
  try { m = message(request.data || {}); } catch (error) { throw new HttpsError('invalid-argument', error.message); }
  let uid = '';
  if (m.audience === 'person') {
    try { uid = m.person.includes('@') ? (await getAuth().getUserByEmail(m.person)).uid : (await getAuth().getUser(m.person)).uid; } catch (_) { throw new HttpsError('not-found', 'No account with that email or id.'); }
  }
  const ref = db.collection('pushLog').doc();
  const nid = ref.id;
  const {uids, off} = await recipients({audience: m.audience, town: m.town, uid});
  await ref.set({
    nid, title: m.title, body: m.body, audience: m.audience, town: m.town, uid: uid || null, person: m.person || null,
    recipients: uids.length, sent: 0, devices: 0, noToken: 0, failed: 0, off, opened: 0, status: 'sending',
    createdAt: FieldValue.serverTimestamp(), createdBy: request.auth.uid,
  });
  const totals = {sent: 0, devices: 0, noToken: 0, failed: 0};
  const link = `https://e-commerce-app-a3897.web.app/?nid=${nid}`;
  for (let i = 0; i < uids.length; i += 50) {
    const slice = uids.slice(i, i + 50);
    const results = await Promise.all(slice.map(u => deliverTo(u, {title: m.title, body: m.body}, {type: 'admin', nid}, link).catch(() => ({status: 'failed', devices: 0}))));
    const batch = db.batch();
    results.forEach((r, j) => {
      if (r.status === 'sent') totals.sent++; else if (r.status === 'no-token') totals.noToken++; else totals.failed++;
      totals.devices += r.devices;
      batch.set(ref.collection('recipients').doc(slice[j]), {uid: slice[j], status: r.status, devices: r.devices, at: FieldValue.serverTimestamp()});
    });
    await batch.commit();
  }
  await ref.update({...totals, status: 'done', doneAt: FieldValue.serverTimestamp()});
  return {nid, recipients: uids.length, off, ...totals};
});

exports.trackPushOpen = onCall({...options, maxInstances: 10}, async request => {
  const nid = typeof request.data?.nid === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(request.data.nid) ? request.data.nid : '';
  const type = typeof request.data?.type === 'string' && /^[A-Za-z0-9_-]{1,40}$/.test(request.data.type) ? request.data.type : '';
  const uid = request.auth?.uid;
  if (nid && uid) {
    const recipientRef = db.collection('pushLog').doc(nid).collection('recipients').doc(uid);
    const first = await db.runTransaction(async tx => {
      const r = await tx.get(recipientRef);
      if (!r.exists || r.data().openedAt) return false;
      tx.update(recipientRef, {openedAt: FieldValue.serverTimestamp()});
      tx.update(db.collection('pushLog').doc(nid), {opened: FieldValue.increment(1)});
      return true;
    });
    return {counted: first};
  }
  if (type && type !== 'admin') {
    await db.collection('pushTypeDaily').doc(`${type}~${dayKey()}`).set({type, day: dayKey(), opened: FieldValue.increment(1)}, {merge: true});
    return {counted: true};
  }
  return {counted: false};
});

exports.pushAudience = onCall(options, async request => {
  await requireAdmin(request);
  const on = (await db.collection('notificationSubscribers').where('enabled', '==', true).count().get()).data().count;
  const offCount = (await db.collection('notificationSubscribers').where('enabled', '==', false).count().get()).data().count;
  const towns = {};
  let scanned = 0;
  for await (const doc of subscribers(db.collection('notificationSubscribers').where('enabled', '==', true).orderBy('__name__'))) {
    const town = placeForPincode(String(doc.data().pincode || ''))?.town || 'Unknown';
    const key = townKey(town) || 'unknown';
    towns[key] = towns[key] || {town: key === 'unknown' ? 'Unknown' : town.replace(/^.*\(([^)]+)\).*$/, '$1'), count: 0};
    towns[key].count++;
    if (++scanned >= MAX_RECIPIENTS) break;
  }
  return {on, off: offCount, towns: Object.values(towns).sort((a, b) => b.count - a.count)};
});

exports.pushNotOpened = onCall(options, async request => {
  await requireAdmin(request);
  const nid = typeof request.data?.nid === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(request.data.nid) ? request.data.nid : '';
  if (!nid) throw new HttpsError('invalid-argument', 'Choose a notification.');
  const sent = await db.collection('pushLog').doc(nid).collection('recipients').where('status', '==', 'sent').limit(1000).get();
  const waiting = sent.docs.filter(d => !d.data().openedAt).map(d => d.id);
  const people = [];
  for (let i = 0; i < waiting.length; i += 100) {
    const found = await getAuth().getUsers(waiting.slice(i, i + 100).map(uid => ({uid})));
    const byUid = new Map(found.users.map(u => [u.uid, u]));
    for (const uid of waiting.slice(i, i + 100)) people.push({uid, email: byUid.get(uid)?.email || '', name: byUid.get(uid)?.displayName || ''});
  }
  return {people, total: waiting.length};
});

/// Counts an automatic notification of [type] sent to [devices] devices today (called by notifications.js after each delivery).
async function countAutomaticSent(type, devices) {
  if (!type || !devices) return;
  try {
    await db.collection('pushTypeDaily').doc(`${type}~${dayKey()}`).set({type, day: dayKey(), sent: FieldValue.increment(devices)}, {merge: true});
  } catch (error) { console.warn('Push count failed', error.message); }
}

exports._pushCenter = {message, recipients, townKey, countAutomaticSent, MAX_RECIPIENTS};
