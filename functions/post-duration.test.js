// One post duration for everyone (functions/post-duration.js) and the two scheduled jobs that replaced the 13 (functions/scheduled-jobs.js).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
const {POST_DURATIONS, DAY_MS, postDurationKey, postDurationMs, cappedEnd, recapLivePosts, applyPostDurationIfChanged} = require('./post-duration');
const {freshPriceFields} = require('./vendor-prices');
const {runAll, hourlyPieces, quarterHourPieces, TASK_NAMES, scheduledJobs} = require('./scheduled-jobs');
const {task} = require('./task');

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const NOW = Date.parse('2026-11-12T10:00:00+05:30');
const iso = ms => new Date(ms).toISOString();

test('the admin chooses 24 hours, 7 days or 1 month; anything else is 24 hours', () => {
  assert.deepEqual(Object.keys(POST_DURATIONS), ['24h', '7d', '1m']);
  assert.equal(postDurationMs({postDuration: '7d'}), 7 * DAY_MS);
  assert.equal(postDurationMs({postDuration: '1m'}), 30 * DAY_MS);
  for (const odd of [undefined, {}, {postDuration: ''}, {postDuration: '3d'}, {postDuration: 'toString'}, null]) {
    assert.equal(postDurationKey(odd), '24h', JSON.stringify(odd));
    assert.equal(postDurationMs(odd), DAY_MS);
  }
});

test('a post ends at its own end or the duration after it was posted, whichever is first', () => {
  assert.equal(cappedEnd(NOW, DAY_MS), NOW + DAY_MS);
  assert.equal(cappedEnd(NOW, DAY_MS, NOW + 7 * DAY_MS), NOW + DAY_MS, 'paid days are capped too');
  assert.equal(cappedEnd(NOW, 30 * DAY_MS, NOW + 7 * DAY_MS), NOW + 7 * DAY_MS, 'the vendor\'s shorter choice stays');
  assert.equal(cappedEnd(NOW, DAY_MS, NaN), NOW + DAY_MS);
});

test('a vendor price lasts the given duration', () => {
  const fields = freshPriceFields(NOW, 7 * DAY_MS);
  assert.equal(fields.priceSetAt, iso(NOW));
  assert.equal(fields.priceExpiresAt, iso(NOW + 7 * DAY_MS));
  assert.equal(fields.endsAt, fields.priceExpiresAt);
  assert.equal(freshPriceFields(NOW).priceExpiresAt, iso(NOW + DAY_MS), '24 hours when no duration is given');
});

test('a changed duration recalculates the running posts once, and gives back time up to the vendor\'s own end', emulated, async () => {
  const db = getFirestore();
  const tag = `pd${Date.now()}`;
  const now = Date.now();
  const posted = now - 2 * 60 * 60 * 1000;
  await db.doc(`products/${tag}-price`).set({name: 'Rice', price: 40, ...freshPriceFields(posted, DAY_MS)});
  await db.doc(`products/${tag}-excl`).set({name: 'Saree', isExclusive: true, active: true, createdAt: Timestamp.fromMillis(posted), expiresAt: iso(posted + 90 * DAY_MS)});
  await db.doc(`vendorTodaysOffers/${tag}_1`).set({vendorId: tag, submittedAt: Timestamp.fromMillis(posted), endsAt: Timestamp.fromMillis(posted + 7 * DAY_MS)});
  await db.doc(`vendorOffers/${tag}`).set({vendorId: tag, status: 'live', createdAt: Timestamp.fromMillis(posted), endsAt: Timestamp.fromMillis(posted + 30 * DAY_MS)});
  await db.doc(`vendorOffers/${tag}-removed`).set({vendorId: tag, status: 'removed', createdAt: Timestamp.fromMillis(posted), endsAt: Timestamp.fromMillis(posted + 30 * DAY_MS)});
  await db.doc(`ads/${tag}`).set({source: 'vendor', startsAt: iso(posted), endsAt: iso(posted + 365 * DAY_MS)});
  await db.doc(`ads/${tag}-admin`).set({startsAt: iso(posted), endsAt: iso(posted + 365 * DAY_MS)});
  const read = async () => ({
    price: (await db.doc(`products/${tag}-price`).get()).data(),
    excl: (await db.doc(`products/${tag}-excl`).get()).data(),
    box: (await db.doc(`vendorTodaysOffers/${tag}_1`).get()).data(),
    offer: (await db.doc(`vendorOffers/${tag}`).get()).data(),
    removed: (await db.doc(`vendorOffers/${tag}-removed`).get()).data(),
    ad: (await db.doc(`ads/${tag}`).get()).data(),
    adminAd: (await db.doc(`ads/${tag}-admin`).get()).data(),
  });

  // 24 hours: every post ends a day after it was posted.
  await recapLivePosts(db, DAY_MS, now);
  let s = await read();
  assert.equal(s.price.priceExpiresAt, iso(posted + DAY_MS));
  assert.equal(s.excl.expiresAt, iso(posted + DAY_MS));
  assert.equal(s.excl.endsAt, iso(posted + DAY_MS), 'the website and the apps hide the exclusive item at that time');
  assert.equal(s.box.endsAt.toMillis(), posted + 7 * DAY_MS, "a Today's Offers box runs with the plan, never capped (owner, 13 Nov 2026)");
  assert.equal(s.offer.endsAt.toMillis(), posted + DAY_MS);
  assert.equal(s.removed.endsAt.toMillis(), posted + 30 * DAY_MS, 'a removed offer is not touched');
  assert.equal(s.ad.endsAt, iso(posted + DAY_MS));
  assert.equal(s.adminAd.endsAt, iso(posted + 365 * DAY_MS), 'the admin\'s own ads are not posts');

  // 1 month: each gets back time up to its own end (the box's 7 days, the offer's 30), the price lasts the month.
  await recapLivePosts(db, 30 * DAY_MS, now);
  s = await read();
  assert.equal(s.price.priceExpiresAt, iso(posted + 30 * DAY_MS));
  assert.equal(s.excl.expiresAt, iso(posted + 30 * DAY_MS));
  assert.equal(s.box.endsAt.toMillis(), posted + 7 * DAY_MS);
  assert.equal(s.offer.endsAt.toMillis(), posted + 30 * DAY_MS);
  assert.equal(s.ad.endsAt, iso(posted + 30 * DAY_MS));

  // Nothing changes a second time.
  assert.equal(await recapLivePosts(db, 30 * DAY_MS, now), 0);
  for (const path of [`products/${tag}-price`, `products/${tag}-excl`, `vendorTodaysOffers/${tag}_1`, `vendorOffers/${tag}`, `vendorOffers/${tag}-removed`, `ads/${tag}`, `ads/${tag}-admin`]) await db.doc(path).delete();
});

test('the 15-minute job applies the admin\'s duration only when it changed', emulated, async () => {
  const db = getFirestore();
  await db.doc('_jobState/postDuration').delete();
  await db.doc('settings/business').set({postDuration: '7d'}, {merge: true});
  try {
    assert.equal((await applyPostDurationIfChanged(db)).durationMs, 7 * DAY_MS);
    assert.equal((await db.doc('_jobState/postDuration').get()).data().durationMs, 7 * DAY_MS);
    assert.deepEqual(await applyPostDurationIfChanged(db), {changed: 0, durationMs: 7 * DAY_MS}, 'unchanged: two reads, no work');
  } finally {
    await db.doc('settings/business').set({postDuration: FieldValue.delete()}, {merge: true});
    await db.doc('_jobState/postDuration').delete();
  }
});

test('the hourly job runs each piece at its hour in India; the 15-minute job runs the expiry pieces', () => {
  const tasks = Object.fromEntries(TASK_NAMES.map(name => [name, task(() => name)]));
  const at = (h, day = 16) => hourlyPieces(tasks, Date.UTC(2026, 10, day, h, 20) - 5.5 * 3600000).map(([name]) => name);
  assert.deepEqual(at(0), ['staffAreaNightly', 'aiAgentHealthCheck']);
  assert.deepEqual(at(3), ['sweepInactiveAccounts', 'dailyStorageMaintenance', 'aiAgentDailyBackup', 'weeklyStorageUsage'], '16 Nov 2026 is a Monday');
  assert.deepEqual(at(3, 17), ['sweepInactiveAccounts', 'dailyStorageMaintenance', 'aiAgentDailyBackup']);
  assert.deepEqual(at(8), ['sendAdSummaries']);
  assert.deepEqual(at(17), ['staffAreaLastChance']);
  assert.deepEqual(at(6), ['aiAgentHealthCheck']);
  assert.deepEqual(at(5), []);
  assert.deepEqual(quarterHourPieces(tasks).map(([name]) => name), ['postDuration', 'expireVendorPrices', 'expireQuickItems', 'clearTodaysOffers', 'expirePremiumStatus', 'notifyNewOffers']);
});

test('one failing piece does not stop the others', async () => {
  const ran = [];
  const failed = await runAll([['a', () => ran.push('a')], ['b', () => { throw Error('boom'); }], ['c', () => ran.push('c')]]);
  assert.deepEqual(ran, ['a', 'c']);
  assert.deepEqual(failed, ['b']);
});
