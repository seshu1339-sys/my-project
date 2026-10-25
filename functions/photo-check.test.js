const {test} = require('node:test');
const assert = require('node:assert/strict');
require('./index'); // starts the Firebase app that photo-check.js uses
const {_photoCheck} = require('./photo-check');

/// A test picture: a smooth pattern ([flip] makes a different picture), as a JPEG of [size] pixels.
async function picture({flip = false, size = 64, quality = 90} = {}) {
  const sharp = require('sharp');
  const raw = Buffer.alloc(64 * 64 * 3);
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      const v = Math.round(128 + 100 * Math.sin((flip ? 63 - x : x) / 5) * Math.cos(y / 7));
      raw.fill(v, (y * 64 + x) * 3, (y * 64 + x) * 3 + 3);
    }
  }
  return sharp(raw, {raw: {width: 64, height: 64, channels: 3}}).resize(size, size).jpeg({quality}).toBuffer();
}

test('whose photo a path is, which paths can be checked, and what Google\'s answer means', () => {
  assert.deepEqual(_photoCheck.describePath('staffAdditions/s1/add1/item2_3'), {kind: 'staffAddition', ownerId: 'add1', label: 'item 2 photo 3'});
  assert.deepEqual(_photoCheck.describePath('vendorShopPhotos/v1/shopPhoto1'), {kind: 'vendor', ownerId: 'v1', label: 'shop photo 1'});
  assert.equal(_photoCheck.describePath('providerApplications/p1/photo').label, 'provider photo');
  assert.equal(_photoCheck.checkId('vendorShopPhotos/v1/shopPhoto1'), 'vendorShopPhotos~v1~shopPhoto1');
  for (const ok of ['staffAdditions/s1/add1/vendor_1', 'staffAdditions/s1/add1/work_2', 'vendorShopPhotos/v1/shopPhoto3', 'vendorApplications/v1/shopPhoto', 'providerApplications/p1/photo', 'fieldSubmissions/s1/123_1']) assert.ok(_photoCheck.CHECKABLE.test(ok), ok);
  for (const bad of ['catalog/x.jpg', 'staffAdditions/s1/add1/../../x', 'users/u1/secret', 'staffAdditions/s1/add1/vendor_9']) assert.ok(!_photoCheck.CHECKABLE.test(bad), bad);
  assert.equal(_photoCheck.onlineVerdict({}).online, 'none');
  assert.equal(_photoCheck.onlineVerdict({partialMatchingImages: [{url: 'https://a.example/x.jpg'}]}).online, 'partial');
  const full = _photoCheck.onlineVerdict({fullMatchingImages: [{url: 'https://a.example/x.jpg'}], pagesWithMatchingImages: [{url: 'https://shop.example', pageTitle: '<b>Fresh</b> tomatoes'}], bestGuessLabels: [{label: 'tomato'}]});
  assert.deepEqual([full.online, full.matches, full.pages, full.bestGuess], ['full', ['https://a.example/x.jpg'], [{url: 'https://shop.example', title: 'Fresh tomatoes'}], 'tomato']);
  assert.equal(_photoCheck.monthKey(Date.parse('2026-10-31T20:00:00Z')), '2026-11', 'the month in India');
});

test('a resized, recompressed copy has nearly the same fingerprint; a different picture does not', async () => {
  const original = await _photoCheck.fingerprint(await picture());
  const copy = await _photoCheck.fingerprint(await picture({size: 48, quality: 55}));
  const other = await _photoCheck.fingerprint(await picture({flip: true}));
  assert.match(original, /^[0-9a-f]{16}$/);
  assert.ok(_photoCheck.distance(original, copy) <= 6, `copy distance ${_photoCheck.distance(original, copy)}`);
  assert.ok(_photoCheck.distance(original, other) > 6, `other distance ${_photoCheck.distance(original, other)}`);
  assert.equal(await _photoCheck.fingerprint(Buffer.from([0xff, 0xd8, 0xff])), '', 'not an image: no fingerprint');
});

test('the admin\'s Google check: online matches, the same photo used before, and at most the free scans a month', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  for (const c of ['photoChecks', 'photoFingerprints', 'photoCheckUsage']) for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  await db.collection('settings').doc('photoCheck').delete();
  await db.collection('_adminSessions').doc('checker').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  const admin = {auth: {uid: 'checker', token: {admin: true, email_verified: true}}};
  const check = path => fns.checkPhoto.run({...admin, data: {path}});
  const save = async (path, bytes) => bucket.file(path).save(bytes, {metadata: {contentType: 'image/jpeg'}});
  let googleSays = {};
  let calls = 0;
  _photoCheck.setWebDetection(async () => {
    calls++;
    if (googleSays === 'down') throw Error('Cloud Vision API has not been used in project 123 before or it is disabled.');
    return googleSays;
  });

  // ---- only the admin, only the photos under review
  await assert.rejects(() => fns.checkPhoto.run({auth: {uid: 'u1', token: {email_verified: true}}, data: {path: 'vendorShopPhotos/v1/shopPhoto1'}}), /Administrator/);
  await assert.rejects(() => check('catalog/x.jpg'), /cannot be checked/);
  await assert.rejects(() => check('vendorShopPhotos/nobody/shopPhoto1'), /not there/);

  // ---- not online, nothing like it before
  await save('vendorShopPhotos/pcV1/shopPhoto1', await picture());
  let result = await check('vendorShopPhotos/pcV1/shopPhoto1');
  assert.deepEqual([result.online, result.duplicates, result.label], ['none', [], 'shop photo 1']);
  assert.equal((await db.collection('photoChecks').doc('vendorShopPhotos~pcV1~shopPhoto1').get()).data().online, 'none');

  // ---- the same picture again (resized and recompressed) from a staff member: a duplicate; and Google finds it online
  await save('staffAdditions/pcStaff/pcAdd1/vendor_1', await picture({size: 48, quality: 55}));
  googleSays = {fullMatchingImages: [{url: 'https://stock.example/shop.jpg'}], pagesWithMatchingImages: [{url: 'https://stock.example', pageTitle: 'Stock photos'}]};
  result = await check('staffAdditions/pcStaff/pcAdd1/vendor_1');
  assert.equal(result.online, 'full');
  assert.deepEqual(result.matches, ['https://stock.example/shop.jpg']);
  assert.deepEqual(result.duplicates.map(d => [d.path, d.kind, d.ownerId, d.label, d.exact]), [['vendorShopPhotos/pcV1/shopPhoto1', 'vendor', 'pcV1', 'shop photo 1', false]]);
  // the exact same file elsewhere is an exact duplicate
  await save('providerApplications/pcP1/photo', await picture());
  googleSays = {};
  result = await check('providerApplications/pcP1/photo');
  assert.ok(result.duplicates.some(d => d.path === 'vendorShopPhotos/pcV1/shopPhoto1' && d.exact));
  // a different picture is not a duplicate; checking a photo again does not list itself
  await save('staffAdditions/pcStaff/pcAdd1/item1_1', await picture({flip: true}));
  assert.deepEqual((await check('staffAdditions/pcStaff/pcAdd1/item1_1')).duplicates, []);
  assert.deepEqual((await check('staffAdditions/pcStaff/pcAdd1/item1_1')).duplicates, []);

  // ---- every Google scan is counted for the month; at the limit the check still finds duplicates but does not ask Google
  const month = _photoCheck.monthKey();
  assert.equal((await db.collection('photoCheckUsage').doc(month).get()).data().scans, 5);
  await db.collection('settings').doc('photoCheck').set({monthlyLimit: 5});
  const before = calls;
  result = await check('vendorShopPhotos/pcV1/shopPhoto1');
  assert.equal(result.online, 'limit');
  assert.equal(calls, before, 'Google was not asked');
  assert.ok(result.duplicates.length > 0);
  assert.equal((await db.collection('photoCheckUsage').doc(month).get()).data().scans, 5);

  // ---- Cloud Vision switched off: the check says so and the scan is not counted
  await db.collection('settings').doc('photoCheck').set({monthlyLimit: 1000});
  googleSays = 'down';
  result = await check('providerApplications/pcP1/photo');
  assert.equal(result.online, 'error');
  assert.match(result.note, /disabled/);
  assert.equal((await db.collection('photoCheckUsage').doc(month).get()).data().scans, 5);

  // ---- which photos of a list still need a check
  assert.deepEqual(await _photoCheck.uncheckedPhotos(['vendorShopPhotos/pcV1/shopPhoto1', 'staffAdditions/pcStaff/pcAdd1/vendor_2']), ['staffAdditions/pcStaff/pcAdd1/vendor_2']);
  _photoCheck.setWebDetection(async () => ({}));
});
