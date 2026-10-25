const {test} = require('node:test');
const assert = require('node:assert/strict');
require('./index'); // starts the Firebase app that shop-ads.js uses
const {_shopAds} = require('./shop-ads');
const {normalizeBatch, recordAdEvents} = require('./ad-tracking');

test('the box count and the shop-ad ids', () => {
  assert.equal(_shopAds.boxCount({}), 15, '15 boxes until the admin changes it');
  assert.equal(_shopAds.boxCount({count: 4}), 4);
  assert.equal(_shopAds.boxCount({count: 500}), 60);
  assert.equal(_shopAds.boxCount({count: -2}), 0);
  assert.equal(_shopAds.isRightBoxAd('rbox-3-abc'), true);
  assert.equal(_shopAds.isRightBoxAd('ad1'), false);
  assert.equal(_shopAds.isRightBoxAd(undefined), false);
});

test('a vendor ticks "Ad for your shop"; the admin links a Right Side Ad Box to the vendor; the box\'s views add up for that vendor from the start of the ad', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  for (const c of ['rightBoxAds', 'adStats', 'adStatsDaily', 'adViews', 'adViewGuard', 'adUniques', 'vendorNotices']) {
    for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  }
  await db.collection('settings').doc('rightAdBoxes').set({count: 5, box3Image: 'https://example.test/sale.jpg'});
  await db.collection('settings').doc('adsConfig').delete();
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('vendors').doc('adV1').set({vendorId: 'adV1', name: 'Lakshmi Kirana', shopId: 'adV1', status: 'approved', vendorCode: 'VEN-NRPM-116-001'});
  await db.collection('vendors').doc('adV2').set({vendorId: 'adV2', name: 'Ravi Fruits', shopId: 'adV2', status: 'approved'});
  await db.collection('vendors').doc('adOff').set({vendorId: 'adOff', name: 'Closed Shop', status: 'suspended'});
  const as = uid => ({auth: {uid, token: {email_verified: true}}});
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  const link = (box, vendorId) => fns.assignRightBoxVendor.run({...admin, data: {box, vendorId}});

  // ---- the tick: only an approved vendor, and only yes / no
  assert.deepEqual(await fns.setAdInterest.run({...as('adV1'), data: {interested: true}}), {interested: true});
  assert.equal((await db.collection('vendors').doc('adV1').get()).data().adInterest, true);
  assert.ok((await db.collection('vendors').doc('adV1').get()).data().adInterestAt);
  await fns.setAdInterest.run({...as('adV2'), data: {interested: true}});
  await fns.setAdInterest.run({...as('adV2'), data: {interested: false}});
  assert.equal((await db.collection('vendors').doc('adV2').get()).data().adInterest, false);
  await assert.rejects(() => fns.setAdInterest.run({...as('adOff'), data: {interested: true}}), /approved/);
  await assert.rejects(() => fns.setAdInterest.run({...as('nobody'), data: {interested: true}}), /approved/);
  await assert.rejects(() => fns.setAdInterest.run({...as('adV1'), data: {interested: 'yes'}}), /Say whether/);

  // ---- only the admin links a box, to an approved vendor, in a box that exists
  await assert.rejects(() => fns.assignRightBoxVendor.run({...as('adV1'), data: {box: 3, vendorId: 'adV1'}}), /Administrator/);
  await assert.rejects(() => link(9, 'adV1'), /no Right Side Ad Box 9/);
  await assert.rejects(() => link(0, 'adV1'), /Choose a Right Side Ad Box/);
  await assert.rejects(() => link(3, 'adOff'), /approved vendor/);
  await assert.rejects(() => link(3, 'a/b'), /Choose a vendor/);

  // ---- linked: a new ad starts; the public settings get only its id; the vendor is told
  const first = await link(3, 'adV1');
  assert.match(first.adId, /^rbox-3-[A-Za-z0-9]{20}$/);
  assert.equal(first.started, true);
  const settings = (await db.collection('settings').doc('rightAdBoxes').get()).data();
  assert.equal(settings.box3AdId, first.adId);
  assert.equal(settings.box3Image, 'https://example.test/sale.jpg', 'the photo stays as it was');
  assert.equal(JSON.stringify(settings).includes('adV1'), false, 'who the vendor is never goes into the public settings');
  const ad = (await db.collection('rightBoxAds').doc(first.adId).get()).data();
  assert.deepEqual([ad.box, ad.vendorId, ad.vendorName, ad.vendorCode, ad.shopId, ad.status, ad.payment], [3, 'adV1', 'Lakshmi Kirana', 'VEN-NRPM-116-001', 'adV1', 'live', 'offline']);
  assert.ok(ad.startedAt);
  const notices = (await db.collection('vendorNotices').where('vendorId', '==', 'adV1').get()).docs.map(d => d.data());
  assert.equal(notices.length, 1);
  assert.equal(notices[0].title, 'Your shop ad is live');
  // the same vendor again (for example after a new photo): the same ad goes on
  assert.deepEqual(await link(3, 'adV1'), {adId: first.adId, started: false});

  // ---- views: counted like every other ad, once per device per 30 minutes, never the vendor's own
  const V = 'visitor-0123456789abcdef', W = 'visitor-fedcba9876543210';
  const view = (visitorId, adId = first.adId) => normalizeBatch({visitorId, town: 'Narsipatnam', events: [{type: 'view', adId, seconds: 1}]});
  const ctx = (auth = null) => ({userAgent: 'Mozilla/5.0 Chrome/120', auth, staffUids: []});
  const t0 = Date.parse('2031-03-05T10:00:00Z');
  assert.equal((await recordAdEvents(db, view(V), ctx(), t0)).views, 1);
  assert.equal((await recordAdEvents(db, view(V), ctx(), t0 + 60000)).views, 0, 'the same device again within 30 minutes');
  assert.equal((await recordAdEvents(db, view(W), ctx(), t0 + 120000)).views, 1);
  assert.equal((await recordAdEvents(db, view(V), ctx({uid: 'adV1', token: {}}), t0 + 40 * 60000)).ignored, 1, 'the vendor looking at their own ad');
  assert.equal((await recordAdEvents(db, normalizeBatch({visitorId: V, events: [{type: 'tap', adId: first.adId}]}), ctx(), t0 + 41 * 60000)).taps, 1);
  let stats = (await db.collection('adStats').doc(first.adId).get()).data();
  assert.deepEqual([stats.views, stats.unique, stats.taps, stats.vendorId, stats.kind, stats.box], [2, 2, 1, 'adV1', 'rightBox', 3]);
  assert.equal((await db.collection('adStatsDaily').doc(`${first.adId}~2031-03-05`).get()).data().views, 2);

  // ---- another vendor in the same box: the first ad ends (its views stay), the new one starts from 0
  const second = await link(3, 'adV2');
  assert.notEqual(second.adId, first.adId);
  assert.equal((await db.collection('rightBoxAds').doc(first.adId).get()).data().status, 'ended');
  assert.ok((await db.collection('rightBoxAds').doc(first.adId).get()).data().endedAt);
  assert.equal((await db.collection('settings').doc('rightAdBoxes').get()).data().box3AdId, second.adId);
  assert.equal((await recordAdEvents(db, view(W, first.adId), ctx(), t0 + 90 * 60000)).ignored, 1, 'an ended ad counts nothing more');
  assert.equal((await recordAdEvents(db, view(W, second.adId), ctx(), t0 + 90 * 60000)).views, 1);
  stats = (await db.collection('adStats').doc(first.adId).get()).data();
  assert.equal(stats.views, 2, 'the first vendor keeps their total');
  assert.equal((await db.collection('adStats').doc(second.adId).get()).data().views, 1);
  assert.equal((await recordAdEvents(db, view(W, 'rbox-4-nosuchad'), ctx(), t0)).ignored, 1);

  // ---- unlinked: the ad ends and the box has no ad id
  assert.deepEqual(await link(3, ''), {adId: null, ended: second.adId});
  assert.equal((await db.collection('rightBoxAds').doc(second.adId).get()).data().status, 'ended');
  assert.equal((await db.collection('settings').doc('rightAdBoxes').get()).data().box3AdId, undefined);
  assert.deepEqual(await link(3, ''), {adId: null, ended: null}, 'unlinking an empty box changes nothing');
});
