const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {validateWholesale} = require('./rules');
const {saveOffer, deleteOffer} = require('./store');

const NOW = Date.parse('2026-11-02T10:00:00+05:30');
const good = (extra = {}) => ({name: ' Basmati   rice ', photoUrl: 'https://example.com/a.webp', price: 1200, minQuantity: '25 kg', validUntil: NOW + 86400000, wholesaler: 'Sri Traders', phone: '98765 43210', ...extra});

test('what the administrator saves is checked', () => {
  const safe = validateWholesale(good(), NOW);
  assert.equal(safe.name, 'Basmati rice');
  assert.equal(safe.phone, '9876543210');
  assert.throws(() => validateWholesale(good({name: 'x'}), NOW), /item name/);
  assert.throws(() => validateWholesale(good({photoUrl: ''}), NOW), /photo/);
  assert.throws(() => validateWholesale(good({price: 0}), NOW), /price/);
  assert.throws(() => validateWholesale(good({minQuantity: ''}), NOW), /quantity/);
  assert.throws(() => validateWholesale(good({validUntil: NOW}), NOW), /validity/);
  assert.throws(() => validateWholesale(good({wholesaler: ''}), NOW), /wholesaler/);
  assert.throws(() => validateWholesale(good({phone: '12345'}), NOW), /contact number/);
});

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};

test('offers are added, edited and deleted', emulated, async () => {
  const db = getFirestore();
  const {offerId} = await saveOffer(db, good(), NOW);
  const saved = (await db.doc(`wholesaleOffers/${offerId}`).get()).data();
  assert.equal(saved.validUntil.toMillis(), NOW + 86400000);
  await saveOffer(db, good({offerId, price: 1100}), NOW);
  assert.equal((await db.doc(`wholesaleOffers/${offerId}`).get()).data().price, 1100);
  await assert.rejects(saveOffer(db, good({offerId: 'missing'}), NOW), /not found/);
  await deleteOffer(db, offerId);
  assert.equal((await db.doc(`wholesaleOffers/${offerId}`).get()).exists, false);
});
