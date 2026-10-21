const {test} = require('node:test');
const assert = require('node:assert/strict');
const sharp = require('sharp');
const {toWebp, optimizeObject} = require('./image-webp')._imageWebp;

const isWebp = buffer => buffer.subarray(0, 4).toString() === 'RIFF' && buffer.subarray(8, 12).toString() === 'WEBP';
// a busy picture so that JPEG/PNG are not tiny
const picture = async (width, height, format) => {
  const noise = Buffer.alloc(width * height * 3);
  for (let i = 0; i < noise.length; i++) noise[i] = (i * 31 + ((i >> 5) * 17)) % 251;
  return sharp(noise, {raw: {width, height, channels: 3}})[format]().toBuffer();
};

test('a big photo becomes a smaller WebP with its longest side at most 1600 px', async () => {
  const jpeg = await picture(3200, 2400, 'jpeg');
  const webp = await toWebp(jpeg);
  assert.ok(isWebp(webp));
  const meta = await sharp(webp).metadata();
  assert.equal(meta.format, 'webp');
  assert.equal(meta.width, 1600);
  assert.equal(meta.height, 1200);
  assert.ok(webp.length < jpeg.length / 2, `${webp.length} should be far smaller than ${jpeg.length}`);
});

test('a small photo is not enlarged', async () => {
  const meta = await sharp(await toWebp(await picture(400, 300, 'png'))).metadata();
  assert.deepEqual([meta.width, meta.height], [400, 300]);
});

test('the camera rotation is applied, so the photo is never stored sideways', async () => {
  const sideways = await sharp(await picture(800, 400, 'jpeg')).withMetadata({orientation: 6}).jpeg().toBuffer();
  const meta = await sharp(await toWebp(sideways)).metadata();
  assert.deepEqual([meta.width, meta.height], [400, 800]);
});

const emulators = !!(process.env.FIREBASE_STORAGE_EMULATOR_HOST && process.env.FIRESTORE_EMULATOR_HOST);
test('a stored photo is converted in place, keeps its download link, and is not converted twice', {skip: !emulators}, async () => {
  const {initializeApp, getApps} = require('firebase-admin/app');
  if (!getApps().length) initializeApp();
  const {getStorage} = require('firebase-admin/storage');
  const bucket = getStorage().bucket();
  const jpeg = await picture(2400, 1800, 'jpeg');
  const store = (name, buffer, contentType, metadata = {}) => bucket.file(name).save(buffer, {resumable: false, metadata: {contentType, cacheControl: 'public,max-age=3600', metadata}});

  await store('catalog/photo1.jpg', jpeg, 'image/jpeg', {firebaseStorageDownloadTokens: 'token-abc'});
  const done = await optimizeObject(bucket, 'catalog/photo1.jpg', 'image/jpeg');
  assert.equal(done.status, 'converted');
  assert.ok(done.after < done.before);
  const [meta] = await bucket.file('catalog/photo1.jpg').getMetadata();
  assert.equal(meta.contentType, 'image/webp');
  assert.equal(meta.metadata.firebaseStorageDownloadTokens, 'token-abc', 'the download link keeps working');
  assert.equal(meta.metadata.optimized, 'webp');
  assert.equal(meta.cacheControl, 'public,max-age=3600');
  const [stored] = await bucket.file('catalog/photo1.jpg').download();
  assert.ok(isWebp(stored));
  assert.equal((await sharp(stored).metadata()).width, 1600);

  // the upload of the converted file triggers the function again: it must do nothing
  assert.deepEqual(await optimizeObject(bucket, 'catalog/photo1.jpg', 'image/webp'), {status: 'skipped', reason: 'not a JPEG or PNG'});
  await bucket.file('catalog/photo1.jpg').setMetadata({contentType: 'image/jpeg'}); // even if the type were reset, the marker stops a second pass
  assert.deepEqual(await optimizeObject(bucket, 'catalog/photo1.jpg', 'image/jpeg'), {status: 'skipped', reason: 'already optimized'});

  // PNGs in the other photo folders; private application photos too
  const png = await picture(1800, 1200, 'png');
  for (const name of ['quickItems/u1/sub1', 'fieldSubmissions/u1/s_1', 'vendorApplications/u1/vendorPhoto', 'fieldStaffApplications/u1/staffPhoto', 'vendorShopPhotos/u1/shopPhoto1', 'vendorProducts/u1/p.png']) {
    await store(name, png, 'image/png');
    assert.equal((await optimizeObject(bucket, name, 'image/png')).status, 'converted', name);
    assert.equal((await bucket.file(name).getMetadata())[0].contentType, 'image/webp');
  }

  // things that must be left alone
  await store('somewhere/else.jpg', jpeg, 'image/jpeg');
  assert.equal((await optimizeObject(bucket, 'somewhere/else.jpg', 'image/jpeg')).reason, 'not a photo folder');
  await store('catalog/anim.gif', Buffer.from('GIF89a'), 'image/gif');
  assert.equal((await optimizeObject(bucket, 'catalog/anim.gif', 'image/gif')).reason, 'not a JPEG or PNG');
  await store('catalog/broken.jpg', Buffer.from('not an image at all'), 'image/jpeg');
  const broken = await optimizeObject(bucket, 'catalog/broken.jpg', 'image/jpeg');
  assert.equal(broken.status, 'skipped');
  assert.match(broken.reason, /unreadable image/);
  assert.equal((await bucket.file('catalog/broken.jpg').getMetadata())[0].contentType, 'image/jpeg', 'a file it cannot read is left as it was');
  const tiny = await sharp({create: {width: 8, height: 8, channels: 3, background: '#ffffff'}}).jpeg({quality: 100}).toBuffer();
  await store('catalog/tiny.jpg', tiny, 'image/jpeg');
  const kept = await optimizeObject(bucket, 'catalog/tiny.jpg', 'image/jpeg');
  assert.ok(kept.status === 'converted' || kept.reason === 'not smaller');
});
