const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {_ads} = require('./vendor-ads');
const {validateSubmission, submitAd, decideAd, removeAd, setSummary, sendSummaries} = _ads;

const URL_OK = uid => `https://firebasestorage.googleapis.com/v0/b/demo.appspot.com/o/vendorProducts%2F${uid}%2F123.webp?alt=media&token=t`;
const good = (uid = 'v1', extra = {}) => ({contentType: 'imageText', imageUrl: URL_OK(uid), title: 'Diwali sale', text: 'Up to 50% off', package: 'silver', durationDays: 30, ...extra});

test('what a vendor may send is checked', () => {
  const ok = validateSubmission(good(), 'v1');
  assert.equal(ok.package, 'silver');
  assert.equal(ok.durationDays, 30);
  assert.throws(() => validateSubmission(good('v1', {durationDays: 0}), 'v1'), /days/);
  assert.throws(() => validateSubmission(good('v1', {durationDays: 400}), 'v1'), /days/);
  assert.throws(() => validateSubmission(good('v1', {imageUrl: URL_OK('someone-else')}), 'v1'), /own uploads/);
  assert.throws(() => validateSubmission(good('v1', {imageUrl: 'https://evil.example/x.png'}), 'v1'), /own uploads/);
  assert.throws(() => validateSubmission(good('v1', {imageUrl: ''}), 'v1'), /picture/);
  assert.throws(() => validateSubmission({contentType: 'text', package: 'normal', durationDays: 7}, 'v1'), /title/);
  assert.throws(() => validateSubmission(good('v1', {title: 'x'.repeat(81)}), 'v1'), /too long/);
  assert.throws(() => validateSubmission(good('v1', {tapAction: 'call', tapValue: '123'}), 'v1'), /phone/);
  assert.throws(() => validateSubmission(good('v1', {tapAction: 'link', tapValue: 'http://x.test'}), 'v1'), /https/);
  assert.throws(() => validateSubmission(good('v1', {textColor: 'red'}), 'v1'), /colour/);
  assert.equal(validateSubmission(good('v1', {package: 'platinum'}), 'v1').package, 'normal');
});

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
async function setup() {
  const {getFirestore} = require('firebase-admin/firestore');
  const db = getFirestore();
  for (const c of ['ads', 'adsPrivate', 'adSubmissions', 'vendorNotices', 'vendors', 'adStatsDaily']) {
    for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  }
  await db.collection('vendors').doc('v1').set({status: 'approved', name: 'Ramu', shopId: 'v1', vendorCode: 'VN00001', shopName: 'Ramu Kirana'});
  await db.collection('vendors').doc('v2').set({status: 'pending', name: 'New'});
  await db.collection('vendors').doc('v3').set({status: 'approved', name: 'Suspended', suspended: true});
  return db;
}
const t0 = Date.parse('2031-03-05T10:00:00Z');

test('a new ad waits for the admin: nothing goes live by itself', emulator, async () => {
  const db = await setup();
  const result = await submitAd(db, 'v1', good(), t0);
  assert.equal(result.status, 'pending');
  assert.equal((await db.collection('ads').get()).size, 0, 'not on the site');
  const sub = (await db.collection('adSubmissions').doc(result.submissionId).get()).data();
  assert.equal(sub.status, 'pending');
  assert.equal(sub.kind, 'new');
  assert.equal(sub.vendorCode, 'VN00001');
  assert.equal(sub.shopName, 'Ramu Kirana');
  await assert.rejects(() => submitAd(db, 'v2', good('v2'), t0), /approved vendor/);
  await assert.rejects(() => submitAd(db, 'v3', good('v3'), t0), /approved vendor|suspended/);
  await assert.rejects(() => submitAd(db, 'nobody', good('nobody'), t0), /approved vendor/);
});

test('approval makes the ad live for the chosen days and tells the vendor; the vendor can have 5 waiting at most', emulator, async () => {
  const db = await setup();
  const { submissionId } = await submitAd(db, 'v1', good(), t0);
  const decided = await decideAd(db, {submissionId, approved: true}, t0 + 1000);
  assert.equal(decided.status, 'approved');
  const ad = (await db.collection('ads').doc(decided.adId).get()).data();
  assert.equal(ad.status, 'approved');
  assert.equal(ad.active, true);
  assert.equal(ad.vendorId, 'v1');
  assert.equal(ad.title, 'Diwali sale');
  assert.equal(ad.rounds, 2, 'the silver plan');
  assert.equal(new Date(ad.endsAt).getTime() - new Date(ad.startsAt).getTime(), 30 * 86400000);
  assert.equal((await db.collection('adsPrivate').doc(decided.adId).get()).data().paid, false);
  const notices = (await db.collection('vendorNotices').where('vendorId', '==', 'v1').get()).docs.map(d => d.data());
  assert.equal(notices.length, 1);
  assert.equal(notices[0].type, 'approved');
  await assert.rejects(() => decideAd(db, {submissionId, approved: true}), /pending/, 'decided once');
  for (let i = 0; i < 5; i++) await submitAd(db, 'v1', good(), t0 + i);
  await assert.rejects(() => submitAd(db, 'v1', good(), t0), /waiting for approval/);
});

test('rejection needs a reason and the vendor sees it', emulator, async () => {
  const db = await setup();
  const { submissionId } = await submitAd(db, 'v1', good(), t0);
  await assert.rejects(() => decideAd(db, {submissionId, approved: false, reason: '  '}), /reason/);
  await decideAd(db, {submissionId, approved: false, reason: 'The picture is blurry'}, t0);
  const sub = (await db.collection('adSubmissions').doc(submissionId).get()).data();
  assert.equal(sub.status, 'rejected');
  assert.equal(sub.reason, 'The picture is blurry');
  assert.equal((await db.collection('ads').get()).size, 0);
  const n = (await db.collection('vendorNotices').get()).docs[0].data();
  assert.equal(n.type, 'rejected');
  assert.match(n.body, /blurry/);
});

test('a photo change stays pending: the site keeps the old approved photo until the admin approves', emulator, async () => {
  const db = await setup();
  const first = await submitAd(db, 'v1', good(), t0);
  const { adId } = await decideAd(db, {submissionId: first.submissionId, approved: true}, t0);
  const oldUrl = (await db.collection('ads').doc(adId).get()).data().imageUrl;
  const newUrl = `https://firebasestorage.googleapis.com/v0/b/demo.appspot.com/o/vendorProducts%2Fv1%2F999.webp?alt=media&token=t`;
  const change = await submitAd(db, 'v1', good('v1', {adId, imageUrl: newUrl, title: 'New title'}), t0 + 5000);
  assert.equal((await db.collection('adSubmissions').doc(change.submissionId).get()).data().kind, 'change');
  let ad = (await db.collection('ads').doc(adId).get()).data();
  assert.equal(ad.imageUrl, oldUrl, 'still the old photo while pending');
  assert.equal(ad.title, 'Diwali sale');
  await assert.rejects(() => submitAd(db, 'v1', good('v1', {adId}), t0 + 6000), /already waiting/);
  await assert.rejects(() => submitAd(db, 'v2', good('v2', {adId}), t0), /approved vendor/);
  await decideAd(db, {submissionId: change.submissionId, approved: true}, t0 + 7000);
  ad = (await db.collection('ads').doc(adId).get()).data();
  assert.equal(ad.imageUrl, newUrl);
  assert.equal(ad.title, 'New title');
  assert.equal(ad.vendorId, 'v1');
  // and a rejected change leaves the ad as it was
  const second = await submitAd(db, 'v1', good('v1', {adId, imageUrl: oldUrl, title: 'Rejected title'}), t0 + 8000);
  await decideAd(db, {submissionId: second.submissionId, approved: false, reason: 'No'}, t0 + 9000);
  assert.equal((await db.collection('ads').doc(adId).get()).data().title, 'New title');
});

test('the admin can remove a vendor ad at any time', emulator, async () => {
  const db = await setup();
  const { submissionId } = await submitAd(db, 'v1', good(), t0);
  const { adId } = await decideAd(db, {submissionId, approved: true}, t0);
  await removeAd(db, {adId, reason: 'Against the rules'}, t0 + 1000);
  const ad = (await db.collection('ads').doc(adId).get()).data();
  assert.equal(ad.status, 'rejected');
  assert.equal(ad.active, false);
  assert.equal(ad.reason, 'Against the rules');
  const types = (await db.collection('vendorNotices').get()).docs.map(d => d.data().type).sort();
  assert.deepEqual(types, ['approved', 'removed']);
  await assert.rejects(() => removeAd(db, {adId: 'nosuch'}), /not found/);
});

test('summaries: daily every day, weekly on Mondays, with the numbers of the period; only the owner chooses', emulator, async () => {
  const db = await setup();
  const { submissionId } = await submitAd(db, 'v1', good(), t0);
  const { adId } = await decideAd(db, {submissionId, approved: true}, t0);
  await assert.rejects(() => setSummary(db, 'v2', {adId, mode: 'daily'}), /not found/);
  await assert.rejects(() => setSummary(db, 'v1', {adId, mode: 'hourly'}), /daily, weekly or off/);
  await setSummary(db, 'v1', {adId, mode: 'daily'});
  assert.equal((await db.collection('ads').doc(adId).get()).data().summary, 'daily');
  const tuesday = Date.parse('2031-03-04T03:00:00Z'); // 08:30 India, Tuesday
  const monday = Date.parse('2031-03-03T03:00:00Z');
  await db.collection('adStatsDaily').doc(`${adId}~2031-03-03`).set({views: 12, unique: 7, taps: 2, seconds: 90, missed: 1});
  await db.collection('adStatsDaily').doc(`${adId}~2031-03-02`).set({views: 30, unique: 20, taps: 4, seconds: 200, missed: 0});
  assert.equal(await sendSummaries(db, tuesday), 1);
  const daily = (await db.collection('vendorNotices').where('type', '==', 'summary').get()).docs.map(d => d.data());
  assert.equal(daily.length, 1);
  assert.equal(daily[0].period, 'day');
  assert.equal(daily[0].views, 12);
  assert.match(daily[0].body, /12 views, 7 people, 2 taps/);
  await setSummary(db, 'v1', {adId, mode: 'weekly'});
  assert.equal(await sendSummaries(db, tuesday), 0, 'weekly summaries wait for Monday');
  assert.equal(await sendSummaries(db, monday), 1);
  const weekly = (await db.collection('vendorNotices').where('period', '==', 'week').get()).docs[0].data();
  assert.equal(weekly.views, 30, 'the 7 days before Monday: Mar 2 counts, Mar 3 does not');
  await setSummary(db, 'v1', {adId, mode: 'off'});
  assert.equal(await sendSummaries(db, monday), 0);
});

test('the radius of a vendor ad is centred on the vendor shop and the area limit is respected', emulator, async () => {
  const db = await setup();
  await db.collection('vendors').doc('v1').set({status: 'approved', name: 'Ramu', shopId: 'v1', vendorCode: 'VN00001', shopName: 'Ramu Kirana', latitude: 17.667, longitude: 82.612});
  const sub = async () => (await submitAd(db, 'v1', good(), t0)).submissionId;
  await assert.rejects(async () => decideAd(db, {submissionId: await sub(), approved: true, radiusKm: 20}), /from the list/);
  const ok = await decideAd(db, {submissionId: await sub(), approved: true, radiusKm: 25}, t0);
  const ad = (await db.collection('ads').doc(ok.adId).get()).data();
  assert.equal(ad.radiusKm, 25);
  assert.equal(ad.radiusLat, 17.667);
  assert.equal(ad.radiusLng, 82.612);
  assert.equal(ad.radiusShopId, 'v1');
  // no radius: as before
  const plain = await decideAd(db, {submissionId: await sub(), approved: true}, t0);
  assert.equal((await db.collection('ads').doc(plain.adId).get()).data().radiusKm, undefined);
  // the area is already full (limit 1, one radius ad already runs there)
  await db.collection('settings').doc('adsConfig').set({maxPerArea: 1});
  await assert.rejects(async () => decideAd(db, {submissionId: await sub(), approved: true, radiusKm: 10}, t0), /already has 1/);
  await db.collection('settings').doc('adsConfig').delete();
  // a vendor without a saved shop location cannot get a radius
  await db.collection('vendors').doc('v1').set({status: 'approved', name: 'Ramu', shopId: 'v1', vendorCode: 'VN00001'});
  await assert.rejects(async () => decideAd(db, {submissionId: await sub(), approved: true, radiusKm: 10}, t0), /no saved shop location/);
});
