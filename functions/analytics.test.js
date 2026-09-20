const {test} = require('node:test');
const assert = require('node:assert/strict');
const {normalizeEvent, recordEvent, dayKey} = require('./analytics');

test('analytics events are validated', () => {
  const v = 'visitor-0123456789abcdef';
  assert.equal(normalizeEvent({visitorId: v, type: 'visit'}).platform, 'web');
  assert.equal(normalizeEvent({visitorId: v, type: 'visit', platform: 'android'}).platform, 'android');
  assert.throws(() => normalizeEvent({type: 'visit'}));
  assert.throws(() => normalizeEvent({visitorId: 'short', type: 'visit'}));
  assert.throws(() => normalizeEvent({visitorId: v, type: 'purchase'}));
  assert.throws(() => normalizeEvent({visitorId: v, type: 'adClick'}));               // ad required
  assert.throws(() => normalizeEvent({visitorId: v, type: 'adClick', adId: 'a/b'}));   // no path tricks
  assert.throws(() => normalizeEvent({visitorId: v, type: 'visit', sourceAd: {x: 1}}));
  assert.equal(normalizeEvent({visitorId: v, type: 'adImpression', adId: 'ad1', placement: 'nonsense'}).placement, null);
  assert.equal(dayKey(Date.parse('2026-09-20T23:59:59Z')), '2026-09-20');
});

// Sums a sharded counter collection the way the admin screen does.
async function sum(db, collection, prefix) {
  const out = {};
  for (const doc of (await db.collection(collection).get()).docs) {
    if (!doc.id.startsWith(prefix)) continue;
    for (const [k, val] of Object.entries(doc.data())) if (typeof val === 'number') out[k] = (out[k] || 0) + val;
  }
  return out;
}
test('visits, ad impressions and clicks count once per unique visitor, and only impressions/clicks repeat', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const {initializeApp, getApps} = require('firebase-admin/app');
  if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
  const db = getFirestore();
  const now = Date.parse('2031-03-05T10:00:00Z'), day = '2031-03-05';
  const ev = (visitor, type, extra = {}) => recordEvent(db, normalizeEvent({visitorId: visitor + '-0123456789abcdef', type, ...extra}), now);
  await ev('alice', 'visit', {platform: 'web'});
  await ev('alice', 'visit', {platform: 'web'});                       // reload: a visit, not a new visitor
  await ev('bob', 'visit', {platform: 'android'});
  await ev('carol', 'visit', {platform: 'web', sourceAd: 'ad1', placement: 'ad'}); // arrived through an ad
  await ev('alice', 'adImpression', {adId: 'ad1', placement: 'ad'});
  await ev('alice', 'adImpression', {adId: 'ad1', placement: 'ad'});    // seen twice by the same person
  await ev('bob', 'adImpression', {adId: 'ad1', placement: 'ad'});
  await ev('bob', 'adImpression', {adId: 'ad2', placement: 'carousel'});
  await ev('alice', 'adClick', {adId: 'ad1', placement: 'ad'});
  await ev('alice', 'adClick', {adId: 'ad1', placement: 'ad'});
  const d = await sum(db, 'analyticsDaily', day + '~');
  assert.equal(d.visits, 4); assert.equal(d.visitors, 3);
  assert.equal(d.visitsWeb, 3); assert.equal(d.visitsAndroid, 1);
  assert.equal(d.visitsFromAds, 1);
  assert.equal(d.adImpressions, 4); assert.equal(d.adViewers, 2);
  assert.equal(d.adClicks, 2); assert.equal(d.adClickers, 1);
  const t = await sum(db, 'analyticsTotals', 'all~');
  assert.ok(t.visits >= 4 && t.visitors >= 3 && t.adViewers >= 2);
  const ad1 = await sum(db, 'analyticsAds', 'ad1~'), ad2 = await sum(db, 'analyticsAds', 'ad2~');
  assert.equal(ad1.impressions, 3); assert.equal(ad1.uniqueViewers, 2);
  assert.equal(ad1.clicks, 2); assert.equal(ad1.uniqueClickers, 1);
  assert.equal(ad1.visitsFromAds, 1);
  assert.equal(ad2.impressions, 1); assert.equal(ad2.clicks || 0, 0);
  // no personal data: markers hold only hashes and dates
  const marker = (await db.collection('analyticsSeen').limit(1).get()).docs[0];
  assert.ok(marker.id.length === 64 && !JSON.stringify(marker.data()).includes('alice'));
});
