const {test} = require('node:test');
const assert = require('node:assert/strict');
const {normalizeBatch, ignoredBecause, recordAdEvents, dayKey, townKey} = require('./ad-tracking');

const V = 'visitor-0123456789abcdef';
const UA = 'Mozilla/5.0 (Windows NT 10.0) Chrome/120 Safari/537.36';

test('batches are validated', () => {
  assert.equal(normalizeBatch({visitorId: V, events: [{type: 'view', adId: 'ad1', seconds: 1}]}).platform, 'web');
  assert.equal(normalizeBatch({visitorId: V, platform: 'android', events: [{type: 'tap', adId: 'ad1'}]}).platform, 'android');
  assert.throws(() => normalizeBatch({events: [{type: 'view', adId: 'ad1'}]}));
  assert.throws(() => normalizeBatch({visitorId: 'short', events: [{type: 'view', adId: 'ad1'}]}));
  assert.throws(() => normalizeBatch({visitorId: V, events: []}));
  assert.throws(() => normalizeBatch({visitorId: V, events: [{type: 'purchase', adId: 'ad1'}]}));
  assert.throws(() => normalizeBatch({visitorId: V, events: [{type: 'view', adId: 'a/b'}]}));
  assert.throws(() => normalizeBatch({visitorId: V, events: Array.from({length: 51}, () => ({type: 'view', adId: 'ad1'}))}));
  assert.equal(normalizeBatch({visitorId: V, events: [{type: 'time', adId: 'ad1', seconds: 9999}]}).events[0].seconds, 120);
  assert.equal(dayKey(Date.parse('2026-10-26T19:00:00Z')), '2026-10-27', 'the day is the Indian day');
  assert.equal(townKey(' Narsipatnam.. East '), 'narsipatnam_east');
});

test('who is never counted', () => {
  const base = {userAgent: UA, auth: null, ad: {vendorId: 'v1'}, config: {}, visitorId: V};
  assert.equal(ignoredBecause(base), '');
  assert.equal(ignoredBecause({...base, userAgent: 'Googlebot/2.1'}), 'bot');
  assert.equal(ignoredBecause({...base, userAgent: 'HeadlessChrome/120'}), 'bot');
  assert.equal(ignoredBecause({...base, config: {testDevices: `x ${V}`}}), 'test device');
  assert.equal(ignoredBecause({...base, auth: {uid: 'a', token: {admin: true}}}), 'admin');
  assert.equal(ignoredBecause({...base, auth: {uid: 's', token: {}}, staffUids: ['s']}), 'staff');
  assert.equal(ignoredBecause({...base, auth: {uid: 'v1', token: {}}}), 'owner');
  assert.equal(ignoredBecause({...base, auth: {uid: 'someone', token: {}}}), '');
});

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
async function setup() {
  const {getFirestore} = require('firebase-admin/firestore');
  const {initializeApp, getApps} = require('firebase-admin/app');
  if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
  const db = getFirestore();
  for (const c of ['ads', 'adStats', 'adStatsDaily', 'adViews', 'adViewGuard', 'adUniques', 'settings']) {
    for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  }
  await db.collection('ads').doc('ad1').set({title: 'Sale', status: 'approved', vendorId: 'v1', shopId: 'shop1'});
  await db.collection('ads').doc('pending1').set({title: 'New', status: 'pending', vendorId: 'v1'});
  return db;
}
const ctx = (extra = {}) => ({userAgent: UA, auth: null, staffUids: [], ...extra});
const batch = (events, extra = {}) => normalizeBatch({visitorId: V, town: 'Narsipatnam', events, ...extra});
const t0 = Date.parse('2031-03-05T10:00:00Z');

test('a view counts once per device per 30 minutes; refreshing does not inflate it; unique people are counted separately', emulator, async () => {
  const db = await setup();
  const view = {type: 'view', adId: 'ad1', seconds: 1};
  assert.equal((await recordAdEvents(db, batch([view]), ctx(), t0)).views, 1);
  for (let i = 1; i <= 20; i++) assert.equal((await recordAdEvents(db, batch([view]), ctx(), t0 + i * 1000)).views, 0, 'a refresh');
  assert.equal((await recordAdEvents(db, batch([view]), ctx(), t0 + 29 * 60000)).duplicates, 1);
  let stats = (await db.collection('adStats').doc('ad1').get()).data();
  assert.equal(stats.views, 1);
  assert.equal(stats.unique, 1);
  // 31 minutes later the same device is a new view but not a new person
  assert.equal((await recordAdEvents(db, batch([view]), ctx(), t0 + 31 * 60000)).views, 1);
  stats = (await db.collection('adStats').doc('ad1').get()).data();
  assert.equal(stats.views, 2);
  assert.equal(stats.unique, 1);
  // another device is another person
  const other = normalizeBatch({visitorId: 'visitor-fedcba9876543210', town: 'Vizag', platform: 'android', events: [view]});
  assert.equal((await recordAdEvents(db, other, ctx(), t0 + 40 * 60000)).views, 1);
  stats = (await db.collection('adStats').doc('ad1').get()).data();
  assert.equal(stats.views, 3);
  assert.equal(stats.unique, 2);
  assert.equal(stats.vendorId, 'v1');
});

test('on-screen time needs a counted view; misses and every tap are counted', emulator, async () => {
  const db = await setup();
  assert.equal((await recordAdEvents(db, batch([{type: 'time', adId: 'ad1', seconds: 8}]), ctx(), t0)).time, 0, 'no view yet: no time');
  await recordAdEvents(db, batch([{type: 'view', adId: 'ad1', seconds: 1}]), ctx(), t0);
  assert.equal((await recordAdEvents(db, batch([{type: 'time', adId: 'ad1', seconds: 6}]), ctx(), t0 + 7000)).time, 6);
  assert.equal((await recordAdEvents(db, batch([{type: 'miss', adId: 'ad1'}, {type: 'miss', adId: 'ad1'}]), ctx(), t0 + 8000)).missed, 2);
  const taps = await recordAdEvents(db, batch([{type: 'tap', adId: 'ad1'}, {type: 'tap', adId: 'ad1'}, {type: 'tap', adId: 'ad1'}]), ctx(), t0 + 9000);
  assert.equal(taps.taps, 3);
  const stats = (await db.collection('adStats').doc('ad1').get()).data();
  assert.deepEqual([stats.views, stats.seconds, stats.missed, stats.taps], [1, 7, 2, 3]);
});

test('the vendor, admin, staff, bots and test devices are never counted; unapproved ads count nothing', emulator, async () => {
  const db = await setup();
  const view = [{type: 'view', adId: 'ad1', seconds: 1}];
  assert.equal((await recordAdEvents(db, batch(view), ctx({auth: {uid: 'v1', token: {}}}), t0)).ignored, 1);
  assert.equal((await recordAdEvents(db, batch(view), ctx({auth: {uid: 'a', token: {admin: true}}}), t0)).ignored, 1);
  assert.equal((await recordAdEvents(db, batch(view), ctx({auth: {uid: 's', token: {}}, staffUids: ['s']}), t0)).ignored, 1);
  assert.equal((await recordAdEvents(db, batch(view), ctx({userAgent: 'Googlebot/2.1'}), t0)).ignored, 1);
  await db.collection('settings').doc('adsConfig').set({testDevices: V});
  assert.equal((await recordAdEvents(db, batch(view), ctx(), t0)).ignored, 1);
  await db.collection('settings').doc('adsConfig').delete();
  assert.equal((await recordAdEvents(db, batch([{type: 'view', adId: 'pending1', seconds: 1}]), ctx(), t0)).ignored, 1);
  assert.equal((await recordAdEvents(db, batch([{type: 'view', adId: 'nosuch', seconds: 1}]), ctx(), t0)).ignored, 1);
  assert.equal((await db.collection('adStats').get()).size, 0, 'nothing was written');
  assert.equal((await db.collection('adViews').get()).size, 0);
});

test('every counted view and tap is logged with time, town and device, and the day totals break down the same way', emulator, async () => {
  const db = await setup();
  await recordAdEvents(db, batch([{type: 'view', adId: 'ad1', seconds: 1}, {type: 'tap', adId: 'ad1'}]), ctx(), t0);
  await recordAdEvents(db, normalizeBatch({visitorId: 'visitor-fedcba9876543210', town: 'Vizag', platform: 'android', events: [{type: 'view', adId: 'ad1', seconds: 1}]}), ctx(), t0 + 1000);
  const log = (await db.collection('adViews').get()).docs.map(d => d.data());
  assert.equal(log.length, 3);
  const first = log.find(l => l.type === 'view' && l.town === 'Narsipatnam');
  assert.equal(first.device, 'web');
  assert.equal(first.day, '2031-03-05');
  assert.equal(first.at.toMillis(), t0);
  assert.equal(first.adId, 'ad1');
  assert.ok(log.find(l => l.type === 'view' && l.town === 'Vizag' && l.device === 'android'));
  assert.ok(log.find(l => l.type === 'tap'));
  const day = (await db.collection('adStatsDaily').doc('ad1~2031-03-05').get()).data();
  assert.equal(day.views, 2);
  assert.equal(day.taps, 1);
  assert.equal(day.towns.narsipatnam.views, 1);
  assert.equal(day.towns.vizag.views, 1);
  assert.equal(day.devices.web.views, 1);
  assert.equal(day.devices.android.views, 1);
  assert.equal(day.devices.web.taps, 1);
});
