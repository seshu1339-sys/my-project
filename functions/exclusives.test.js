const {test} = require('node:test');
const assert = require('node:assert/strict');

test('Special Category Exclusives: permission, publish, expiry lifecycle', {skip: !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST)}, async () => {
  process.env.PUSH_DRY_RUN = 'true';
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  // Admin callables now also require a fresh OTP-verified session (see admin-otp.js).
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  const vendor = {auth: {uid: 'exV', token: {email_verified: true}}};
  const wipe = async name => { for (const d of (await db.collection(name).get()).docs) await d.ref.delete(); };
  const setPermission = (data, ctx = admin) => fns.setVendorExclusivesPermission.run({...ctx, data});
  const submit = (data, ctx = vendor) => fns.submitExclusiveItem.run({...ctx, data});
  const IMG = 'http://127.0.0.1:9199/v0/b/x/o/vendorProducts%2FexV%2Fitem.jpg?alt=media';
  try {
    await wipe('_pushDryRun'); await wipe('_notificationDeliveries');
    await db.collection('vendors').doc('exV').set({vendorId: 'exV', name: 'Ex Shop', shopId: 'exShop', status: 'approved'});
    await db.collection('vendors').doc('other').set({vendorId: 'other', name: 'Other Shop', status: 'approved'});
    await db.collection('notificationSubscribers').doc('exV').set({enabled: true});
    await db.collection('users').doc('exV').collection('pushTokens').doc('t').set({token: 'tok'});

    // ---- without the permission, nothing works
    await assert.rejects(() => submit({name: 'Design 1', price: 500, imageUrl: IMG, durationDays: 5}), /not enabled/);
    await assert.rejects(() => setPermission({vendorId: 'exV', enabled: true, maxDurationDays: 0}, vendor), /Administrator/);
    await assert.rejects(() => setPermission({vendorId: 'exV', enabled: true, maxDurationDays: 0}), /1 to 365/);

    // ---- admin grants the permission with a maximum duration
    await setPermission({vendorId: 'exV', enabled: true, maxDurationDays: 10});
    let v = (await db.collection('vendors').doc('exV').get()).data();
    assert.equal(v.specialCategoryExclusives, true); assert.equal(v.exclusivesMaxDurationDays, 10);

    // ---- publish: validation, then success (auto-published, no review queue)
    await assert.rejects(() => submit({name: 'D', price: 500, imageUrl: IMG, durationDays: 5}), /name/i);
    await assert.rejects(() => submit({name: 'Design 1', price: -1, imageUrl: IMG, durationDays: 5}), /price/i);
    await assert.rejects(() => submit({name: 'Design 1', price: 500, imageUrl: IMG, durationDays: 11}), /1 to 10/);
    const out = await submit({name: 'Design 1', price: 500, imageUrl: IMG, durationDays: 5});
    assert.equal(out.status, 'active');
    const product = (await db.collection('products').doc(out.productId).get()).data();
    assert.equal(product.name, 'Design 1'); assert.equal(product.price, 500); assert.equal(product.isExclusive, true);
    assert.equal(product.ownerId, 'exV'); assert.equal(product.shopId, 'exShop'); assert.equal(product.active, true);
    assert.ok(product.expiresAt);

    // ---- another vendor without the permission cannot publish
    await assert.rejects(() => submit({name: 'Design 2', price: 100, imageUrl: IMG, durationDays: 1}, {auth: {uid: 'other', token: {email_verified: true}}}), /not enabled/);

    // ---- notify before expiry: an item expiring within the (default 2-day) notice window gets exactly one push
    const soon = db.collection('products').doc();
    await soon.set({name: 'Almost done', price: 10, imageUrl: IMG, isExclusive: true, ownerId: 'exV', shopId: 'exShop', active: true, expiresAt: new Date(Date.now() + 86400000).toISOString()});
    await fns.dailyStorageMaintenance.run({});
    let pushes = (await db.collection('_pushDryRun').get()).docs.map(d => d.data());
    assert.equal(pushes.filter(p => p.data.productId === soon.id).length, 1);
    assert.equal((await soon.get()).data().notifiedExpiryAt !== undefined, true);
    await fns.dailyStorageMaintenance.run({}); // running again must not notify a second time
    pushes = (await db.collection('_pushDryRun').get()).docs.map(d => d.data());
    assert.equal(pushes.filter(p => p.data.productId === soon.id).length, 1);

    // ---- auto-archive at expiry
    const expired = db.collection('products').doc();
    await expired.set({name: 'Gone', price: 20, imageUrl: IMG, isExclusive: true, ownerId: 'exV', shopId: 'exShop', active: true, expiresAt: new Date(Date.now() - 1000).toISOString()});
    await fns.dailyStorageMaintenance.run({});
    let data = (await expired.get()).data();
    assert.equal(data.active, false); assert.ok(data.archivedAt);

    // ---- reactivate within the 15-day window, capped by the vendor's current maximum
    await assert.rejects(() => fns.reactivateExclusiveItem.run({...vendor, data: {productId: expired.id, durationDays: 11}}), /1 to 10/);
    const reactivated = await fns.reactivateExclusiveItem.run({...vendor, data: {productId: expired.id, durationDays: 3}});
    assert.equal(reactivated.status, 'active');
    data = (await expired.get()).data();
    assert.equal(data.active, true); assert.equal(data.archivedAt, undefined);

    // ---- auto-delete after 15 days archived, including its Storage photo
    const {getStorage} = require('firebase-admin/storage');
    const bucket = getStorage().bucket();
    await bucket.file('vendorProducts/exV/gone.jpg').save(Buffer.from([1, 2, 3]));
    const longGone = db.collection('products').doc();
    await longGone.set({
      name: 'Long gone', price: 30, isExclusive: true, ownerId: 'exV', shopId: 'exShop', active: false,
      imageUrl: 'http://127.0.0.1:9199/v0/b/x/o/vendorProducts%2FexV%2Fgone.jpg?alt=media',
      archivedAt: new Date(Date.now() - 16 * 86400000).toISOString(),
    });
    assert.ok((await fns.reactivateExclusiveItem.run({...vendor, data: {productId: longGone.id, durationDays: 1}}).catch(e => e)) instanceof Error, 'reactivating past the 15-day window is refused');
    await fns.dailyStorageMaintenance.run({});
    assert.equal((await longGone.get()).exists, false);
    assert.equal((await bucket.file('vendorProducts/exV/gone.jpg').exists())[0], false);

    // ---- disabling the permission stops new items (existing ones are untouched)
    await setPermission({vendorId: 'exV', enabled: false});
    v = (await db.collection('vendors').doc('exV').get()).data();
    assert.equal(v.specialCategoryExclusives, false); assert.equal(v.exclusivesMaxDurationDays, undefined);
    await assert.rejects(() => submit({name: 'Design 3', price: 100, imageUrl: IMG, durationDays: 1}), /not enabled/);
    assert.equal((await db.collection('products').doc(out.productId).get()).exists, true);
  } finally {
    await wipe('_pushDryRun'); await wipe('_notificationDeliveries');
  }
});
