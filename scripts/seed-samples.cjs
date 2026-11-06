// Sample data for trying the whole LOCAMARKET system: users, vendors, shops, staff, service providers, categories, items, services, ads,
// Right Side Ad Boxes and Today's Offers in five towns. Every record is marked isSample: true and every account is listed in
// _sampleAccounts, so the admin panel shows a SAMPLE label and Settings > Sample data > "Delete all samples" removes all of it.
//
// Vendors, staff and providers are made through the REAL server functions (registerVendor, approveVendor, submitShopPhoto, submitVendorChange,
// requestFieldStaffAccess, registerProvider, submitVendorAd, decideVendorAd, assignRightBoxVendor, ...), exactly as the apps do, so their
// IDs (VEN-NRPM-116-325, STF-..., SRV-...) and records are the real ones. Photos are made here by code: a coloured picture with its name
// written on it ("Sample Shop 1", "Ad Sample 3", "Plumber Sample 2" ...) - no downloads.
//
// LOCAL EMULATORS ONLY (a demo- project): it refuses anything else.
//   node scripts/seed-samples.cjs [--import-live <backup folder>] [--out <file.json>]
//   node scripts/seed-samples.cjs --reset-timers [--out <file.json>]    (only moves the short ad / box timers to start from now)
// The emulators must be running: firebase emulators:start --only auth,firestore,storage,functions --project demo-locamarket
'use strict';
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');

const functionsDir = path.join(__dirname, '..', 'functions');
const need = name => require(require.resolve(name, {paths: [functionsDir]}));
const {initializeApp} = need('firebase-admin/app');
const {getFirestore, FieldValue, Timestamp} = need('firebase-admin/firestore');
const {getAuth} = need('firebase-admin/auth');
const {getStorage} = need('firebase-admin/storage');
const sharp = need('sharp');

const PROJECT = process.env.SAMPLE_PROJECT || 'demo-locamarket';
if (!PROJECT.startsWith('demo-')) throw Error('Sample data is made only in the local Firebase emulators (a demo- project).');
process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ||= '127.0.0.1:9099';
process.env.FIREBASE_STORAGE_EMULATOR_HOST ||= '127.0.0.1:9199';
const BUCKET = `${PROJECT}.appspot.com`;
initializeApp({projectId: PROJECT, storageBucket: BUCKET});
const db = getFirestore();
const auth = getAuth();
const bucket = getStorage().bucket();
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT}/us-central1`;
const AUTH_REST = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const PASSWORD = 'Sample@12345';
const args = process.argv.slice(2);
const arg = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const OUT = arg('--out') || path.join(process.cwd(), 'sample-seed-result.json');
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
const MIN = 60000, HOUR = 3600000, DAY = 86400000;

// ---------------------------------------------------------------------------------------------------------------------------------
// The five towns (real places and coordinates, different districts).
const TOWNS = {
  narsipatnam: {name: 'Narsipatnam', code: 'NRPM', pincode: '531116', lat: 17.6670, lng: 82.6120},
  tuni: {name: 'Tuni', code: 'TUNI', pincode: '533401', lat: 17.3590, lng: 82.5460},
  rajahmundry: {name: 'Rajahmundry', code: 'RAJH', pincode: '533101', lat: 17.0005, lng: 81.8040},
  visakhapatnam: {name: 'Visakhapatnam', code: 'VSKP', pincode: '530002', lat: 17.6868, lng: 83.2185},
  vijayawada: {name: 'Vijayawada', code: 'VJWD', pincode: '520001', lat: 16.5062, lng: 80.6480},
};
const near = (town, dLatKm, dLngKm) => ({lat: +(town.lat + dLatKm / 111).toFixed(6), lng: +(town.lng + dLngKm / (111 * Math.cos(town.lat * Math.PI / 180))).toFixed(6)});

// ---------------------------------------------------------------------------------------------------------------------------------
// Pictures made by code.
const COLORS = ['#2E7D32', '#1565C0', '#EF6C00', '#6A1B9A', '#C62828', '#00838F', '#4E342E', '#AD1457', '#283593', '#558B2F', '#F9A825', '#37474F', '#00695C', '#5D4037', '#7B1FA2', '#0277BD'];
const esc = t => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const hashOf = t => crypto.createHash('sha256').update(t).digest();

/// A plain coloured picture with [title] written on it. Each title gets its own colour, gradient and shapes, so two sample photos are
/// never "the same picture" for the duplicate-photo check.
async function picture(title, {w = 800, h = 600, sub = 'SAMPLE - LOCAMARKET TEST', color} = {}) {
  const hb = hashOf(title);
  const base = color || COLORS[hb[0] % COLORS.length];
  const angle = hb[1] % 4;
  const [x2, y2] = [['100%', '0%'], ['0%', '100%'], ['100%', '100%'], ['0%', '0%']][angle];
  const circles = [0, 1, 2].map(i => `<circle cx="${(hb[2 + i] / 255) * w}" cy="${(hb[5 + i] / 255) * h}" r="${60 + (hb[8 + i] % 120)}" fill="#ffffff" fill-opacity="${0.12 + (hb[11 + i] % 20) / 100}"/>`).join('');
  const size = Math.max(28, Math.min(72, Math.floor((w * 1.7) / Math.max(8, title.length))));
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}">
<defs><linearGradient id="g" x1="0%" y1="0%" x2="${x2}" y2="${y2}"><stop offset="0%" stop-color="${base}"/><stop offset="100%" stop-color="#111111"/></linearGradient></defs>
<rect width="100%" height="100%" fill="url(#g)"/>${circles}
<rect x="16" y="16" width="${w - 32}" height="${h - 32}" fill="none" stroke="#ffffff" stroke-width="5" rx="22"/>
<text x="50%" y="48%" font-family="Arial, Helvetica, sans-serif" font-size="${size}" font-weight="bold" fill="#ffffff" text-anchor="middle" dominant-baseline="middle">${esc(title)}</text>
<text x="50%" y="${h - 48}" font-family="Arial, Helvetica, sans-serif" font-size="${Math.max(16, Math.round(size / 2.6))}" fill="#ffffff" text-anchor="middle">${esc(sub)}</text></svg>`;
  return sharp(Buffer.from(svg)).png().toBuffer();
}

/// Saves bytes in Storage and returns the download link (the emulator's address).
async function save(file, bytes, contentType = 'image/png') {
  const token = crypto.randomUUID();
  await bucket.file(file).save(bytes, {contentType, resumable: false, metadata: {metadata: {firebaseStorageDownloadTokens: token}}});
  return `http://127.0.0.1:9199/v0/b/${BUCKET}/o/${encodeURIComponent(file)}?alt=media&token=${token}`;
}
const slug = t => String(t).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
/// A public sample photo (catalog/sample-...) with [title] on it.
const samplePhoto = async (title, opts) => save(`catalog/sample-${slug(title)}.png`, await picture(title, opts));

// ---------------------------------------------------------------------------------------------------------------------------------
// Accounts and server calls, the way the apps make them.
async function signIn(email) {
  const r = await fetch(`${AUTH_REST}/accounts:signInWithPassword?key=demo`, {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({email, password: PASSWORD, returnSecureToken: true})});
  const j = await r.json();
  if (!j.idToken) throw Error(`sign-in ${email}: ${JSON.stringify(j.error || j)}`);
  return j.idToken;
}
async function account(email, name, role, {sample = true, claims} = {}) {
  let user;
  try { user = await auth.getUserByEmail(email); } catch (_) { user = await auth.createUser({email, password: PASSWORD, displayName: name, emailVerified: true}); }
  if (claims) await auth.setCustomUserClaims(user.uid, claims);
  if (sample) await db.collection('_sampleAccounts').doc(user.uid).set({email, name, role, isSample: true, createdAt: FieldValue.serverTimestamp()}, {merge: true});
  return {uid: user.uid, email, name, role, token: await signIn(email)};
}
async function call(name, data, token) {
  const r = await fetch(`${FUNCTIONS}/${name}`, {method: 'POST', headers: {'content-type': 'application/json', ...(token ? {authorization: `Bearer ${token}`} : {})}, body: JSON.stringify({data})});
  const text = await r.text();
  let j;
  try { j = JSON.parse(text); } catch (_) { throw Error(`${name}: HTTP ${r.status} ${text.slice(0, 300)}`); }
  if (j.error) throw Error(`${name}: ${j.error.message}`);
  return j.result;
}
const mark = (collection, id, extra = {}) => db.collection(collection).doc(id).set({isSample: true, ...extra}, {merge: true});

// ---------------------------------------------------------------------------------------------------------------------------------
// The live site's public settings, categories, products, shops, services and promotions (from scripts/backup-firestore.cjs), so the test
// site looks like the real one. They stay unmarked: they are the "real" records "Delete all samples" must never touch.
function fromRest(v) {
  if (v === null || v === undefined) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('booleanValue' in v) return v.booleanValue;
  if ('nullValue' in v) return null;
  if ('timestampValue' in v) return Timestamp.fromDate(new Date(v.timestampValue));
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, fromRest(x)]));
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fromRest);
  if ('geoPointValue' in v) return v.geoPointValue;
  if ('referenceValue' in v) return v.referenceValue;
  return null;
}
async function importLive(folder) {
  const names = ['settings', 'categories', 'products', 'shops', 'services', 'promotions', 'productImageLibrary', 'locations', 'ads'];
  const counts = {};
  for (const name of names) {
    const file = path.join(folder, `${name}.json`);
    if (!fs.existsSync(file)) continue;
    const docs = JSON.parse(fs.readFileSync(file, 'utf8'));
    let batch = db.batch(), n = 0;
    for (const d of docs) {
      const id = d.name.split('/').pop();
      batch.set(db.collection(name).doc(id), Object.fromEntries(Object.entries(d.fields || {}).map(([k, x]) => [k, fromRest(x)])));
      if (++n % 400 === 0) { await batch.commit(); batch = db.batch(); }
    }
    await batch.commit();
    counts[name] = docs.length;
  }
  log('Imported the live public records:', JSON.stringify(counts));
  return counts;
}

// ---------------------------------------------------------------------------------------------------------------------------------
async function main() {
  const T = Date.now();
  const iso = ms => new Date(ms).toISOString();
  const out = {project: PROJECT, startedAt: iso(T), password: PASSWORD, towns: TOWNS};

  if (args.includes('--reset-timers')) return resetTimers(T, out);
  if (arg('--import-live')) out.imported = await importLive(arg('--import-live'));

  // The administrator who approves everything (a test admin with a valid admin session; not a sample account).
  const admin = await account('admin.test@locamarket.test', 'Test Admin', 'admin', {sample: false, claims: {admin: true}});
  await db.collection('_adminSessions').doc(admin.uid).set({expiresAt: Timestamp.fromMillis(T + 30 * DAY), email: admin.email});
  out.admin = {email: admin.email, uid: admin.uid};
  log('Admin ready', admin.email);

  // City codes for the five towns (the three built-in ones plus Visakhapatnam and Vijayawada); the added rows are marked sample.
  const cityRef = db.collection('settings').doc('cityCodes');
  const existing = (await cityRef.get()).data()?.rows || [];
  const rows = [...existing];
  for (const t of Object.values(TOWNS)) {
    if (!rows.some(r => String(r.code).toUpperCase() === t.code)) rows.push({town: t.name, code: t.code, pincodes: t.pincode, sample: true});
  }
  await cityRef.set({rows}, {merge: true});

  // ---- Categories (4) and the item list vendors choose from (Product Image Library, 8 items).
  const categories = [];
  for (let i = 1; i <= 4; i++) {
    const id = `sample-category-${i}`;
    const kind = ['Vegetables', 'Fruits', 'Grocery', 'Dairy'][i - 1];
    await db.collection('categories').doc(id).set({
      name: `Sample Category ${i}`, description: `Sample ${kind}`, imageUrl: await samplePhoto(`Sample Category ${i}`), order: 900 + i, active: true, parentId: '', isSample: true,
    });
    categories.push({id, kind});
  }
  const LIBRARY = [
    ['Tomato', 1, 'kg'], ['Onion', 1, 'kg'], ['Potato', 1, 'kg'], ['Banana', 2, 'pcs'], ['Apple', 2, 'kg'], ['Rice', 3, 'kg'], ['Toor Dal', 3, 'kg'], ['Milk', 4, 'pcs'],
  ];
  const library = [];
  for (const [i, [item, cat, unit]] of LIBRARY.entries()) {
    const id = `sample-lib-${slug(item)}`;
    const name = `Sample Product ${i + 1} ${item}`;
    await db.collection('productImageLibrary').doc(id).set({
      name, imageUrl: await samplePhoto(`Sample Product ${i + 1}`, {sub: `${item} - SAMPLE`}), categoryId: `sample-category-${cat}`, active: true, order: 900 + i, isSample: true,
    });
    library.push({id, name, item, unit});
  }
  out.categories = categories;
  out.library = library;
  log('Categories and item list ready');

  // ---- Vendors and their shops (12): Narsipatnam 4, the other towns 2 each. The real registration, approval, shop photos and items.
  const PLAN = [
    ['narsipatnam', 0.6, 0.4, 32], ['narsipatnam', -0.8, 1.1, 28], ['narsipatnam', 1.4, -0.9, 35], ['narsipatnam', -1.6, -1.5, 25],
    ['tuni', 0.5, 0.7, 30], ['tuni', -0.9, -0.6, 27],
    ['rajahmundry', 0.8, 0.5, 36], ['rajahmundry', -1.2, 1.0, 31],
    ['visakhapatnam', 0.7, -0.6, 40], ['visakhapatnam', -1.0, 0.8, 34],
    ['vijayawada', 0.9, 0.6, 38], ['vijayawada', -0.7, -1.1, 33],
  ];
  const SECOND = ['sample-lib-onion', 'sample-lib-potato', 'sample-lib-banana', 'sample-lib-rice', 'sample-lib-onion', 'sample-lib-apple', 'sample-lib-toor-dal', 'sample-lib-milk', 'sample-lib-onion', 'sample-lib-rice', 'sample-lib-potato', 'sample-lib-milk'];
  const vendors = [];
  for (const [i, [townKey, dLat, dLng, tomatoPrice]] of PLAN.entries()) {
    const n = i + 1;
    const town = TOWNS[townKey];
    const spot = near(town, dLat, dLng);
    const v = await account(`sample.vendor${n}@samples.locamarket.test`, `Sample Vendor ${n}`, 'vendor');
    await save(`vendorApplications/${v.uid}/vendorPhoto`, await picture(`Sample Vendor ${n}`));
    await save(`vendorApplications/${v.uid}/shopPhoto`, await picture(`Sample Shop ${n}`));
    const phone = `90000000${String(n).padStart(2, '0')}`;
    const reg = await call('registerVendor', {
      ownerName: `Sample Vendor ${n}`, phone, name: `Sample Shop ${n}`, shopCategory: categories[n % 4].kind,
      address: `Sample Street ${n}, ${town.name}`, pincode: town.pincode, description: `Sample Shop ${n}: a sample shop in ${town.name} for testing.`,
      latitude: spot.lat, longitude: spot.lng, gpsAddress: `Near the centre of ${town.name}`,
    }, v.token);
    await call('approveVendor', {vendorId: v.uid, approved: true}, admin.token);
    // Three shop photos, the shop itself first; the admin checks and approves them.
    for (let slot = 1; slot <= 3; slot++) {
      await save(`vendorShopPhotos/${v.uid}/shopPhoto${slot}`, await picture(slot === 1 ? `Sample Shop ${n}` : `Sample Shop ${n} Photo ${slot}`));
      await call('submitShopPhoto', {slot}, v.token);
      await call('reviewShopPhoto', {vendorId: v.uid, slot, approved: true}, admin.token);
    }
    // Two items (the default limit): the same Tomato everywhere at different prices, and one more.
    const items = [];
    items.push(await call('submitVendorChange', {type: 'newProduct', collection: 'products', changes: {libraryItemId: 'sample-lib-tomato', unitType: 'kg', quantity: 1, price: tomatoPrice}}, v.token));
    items.push(await call('submitVendorChange', {type: 'newProduct', collection: 'products', changes: {libraryItemId: SECOND[i], unitType: SECOND[i].includes('banana') || SECOND[i].includes('milk') ? 'pcs' : 'kg', quantity: SECOND[i].includes('banana') ? 6 : 1, price: 20 + ((n * 7) % 40)}}, v.token));
    for (const name of ['vendorApplications', 'vendors', 'shops']) await mark(name, v.uid);
    for (const it of items) await mark('products', it.docId);
    for (let slot = 1; slot <= 3; slot++) await mark('vendorShopPhotos', `${v.uid}_${slot}`);
    await db.collection('users').doc(v.uid).set({name: `Sample Vendor ${n}`, isSample: true}, {merge: true});
    vendors.push({n, uid: v.uid, email: v.email, town: town.name, townKey, vendorCode: reg.vendorCode, phone, shop: `Sample Shop ${n}`, lat: spot.lat, lng: spot.lng, tomatoPrice, items: items.map(x => x.docId)});
    log(`Vendor ${n} ${reg.vendorCode} ${town.name}`);
  }
  out.vendors = vendors;

  // Admin permission for more items: Sample Vendor 1 may have 4; it adds two more.
  await call('setVendorItemLimit', {vendorId: vendors[0].uid, itemLimit: 4}, admin.token);
  const v1 = {token: await signIn(vendors[0].email)};
  for (const [lib, price] of [['sample-lib-apple', 140], ['sample-lib-milk', 30]]) {
    const r = await call('submitVendorChange', {type: 'newProduct', collection: 'products', changes: {libraryItemId: lib, unitType: lib.includes('milk') ? 'pcs' : 'kg', quantity: 1, price}}, v1.token);
    await mark('products', r.docId);
    vendors[0].items.push(r.docId);
  }
  // Vendors 1 and 3 tick "Ad for your shop".
  for (const v of [vendors[0], vendors[2]]) await call('setAdInterest', {interested: true}, await signIn(v.email));
  log('Vendor item limit and ad interest done');

  // ---- Field staff (4), each in another town; Sample Staff 1 has auto-approve ON (the default is OFF).
  const staff = [];
  for (const [i, townKey] of ['narsipatnam', 'tuni', 'rajahmundry', 'visakhapatnam'].entries()) {
    const n = i + 1;
    const town = TOWNS[townKey];
    const spot = near(town, 0.3 * n, -0.2 * n);
    const s = await account(`sample.staff${n}@samples.locamarket.test`, `Sample Staff ${n}`, 'staff');
    await save(`fieldStaffApplications/${s.uid}/staffPhoto`, await picture(`Sample Staff ${n}`));
    const r = await call('requestFieldStaffAccess', {name: `Sample Staff ${n}`, phone: `91000000${String(n).padStart(2, '0')}`, pincode: town.pincode, latitude: spot.lat, longitude: spot.lng, gpsAddress: `${town.name} centre`}, s.token);
    await call('reviewFieldStaff', {staffUid: s.uid, approved: true}, admin.token);
    await mark('fieldStaff', s.uid);
    staff.push({n, uid: s.uid, email: s.email, town: town.name, townKey, staffCode: r.staffCode, phone: `91000000${String(n).padStart(2, '0')}`, lat: spot.lat, lng: spot.lng});
    log(`Staff ${n} ${r.staffCode} ${town.name}`);
  }
  await call('setStaffAutoApprove', {staffUid: staff[0].uid, enabled: true}, admin.token);
  out.staff = staff;

  // ---- Service providers (5) who register themselves; each listing gets 5 work photos.
  const providers = [];
  const PROVIDERS = [['narsipatnam', 'plumber', 'Plumber', 250], ['tuni', 'electrician', 'Electrician', 300], ['rajahmundry', 'carpenter', 'Carpenter', 350], ['visakhapatnam', 'ac_repair', 'AC Repair', 450], ['vijayawada', 'painter', 'Painter', 280]];
  for (const [i, [townKey, typeKey, typeName, rate]] of PROVIDERS.entries()) {
    const n = i + 1;
    const town = TOWNS[townKey];
    const spot = near(town, -0.4 * n, 0.5);
    const p = await account(`sample.provider${n}@samples.locamarket.test`, `Sample Provider ${n}`, 'provider');
    await save(`providerApplications/${p.uid}/photo`, await picture(`Sample Provider ${n}`));
    const r = await call('registerProvider', {
      name: `Sample Provider ${n}`, phone: `92000000${String(n).padStart(2, '0')}`, serviceTypeId: `type-${typeKey}`, hourlyRate: rate,
      address: `Sample Colony ${n}, ${town.name}`, pincode: town.pincode, latitude: spot.lat, longitude: spot.lng,
    }, p.token);
    const ok = await call('approveProvider', {providerId: p.uid, approved: true}, admin.token);
    const extra = [];
    for (let k = 2; k <= 5; k++) extra.push(await samplePhoto(`${typeName} Sample ${n}-${k}`, {sub: `Sample Work Photo ${k}`}));
    await db.collection('services').doc(ok.listingId).set({images: extra, isSample: true, description: `Sample ${typeName} service in ${town.name}. ₹${rate} per hour.`}, {merge: true});
    for (const name of ['providerApplications', 'providers']) await mark(name, p.uid);
    providers.push({n, uid: p.uid, email: p.email, town: town.name, type: typeName, rate, providerCode: r.providerCode, listingId: ok.listingId});
    log(`Provider ${n} ${r.providerCode} ${typeName} ${town.name}`);
  }
  out.providers = providers;

  // ---- A sample listing for EVERY service type (30): 5 photos, a short description, a charge per hour. Services stay in their own collection.
  const types = (await db.collection('services').where('kind', '==', 'serviceType').get()).docs;
  const townKeys = Object.keys(TOWNS);
  const serviceListings = [];
  for (const [i, doc] of types.entries()) {
    const type = doc.data();
    const town = TOWNS[townKeys[i % townKeys.length]];
    const spot = near(town, 0.2 + (i % 3) * 0.3, -0.3);
    const photos = [];
    for (let k = 1; k <= 5; k++) photos.push(await samplePhoto(`${type.name} Sample ${k}`, {sub: `Sample Work Photo ${k}`}));
    const rate = 200 + (i % 8) * 50;
    const id = `sample-service-${type.typeId || doc.id}`;
    await db.collection('services').doc(id).set({
      kind: 'service', name: `${type.name} Sample Provider`, typeId: type.typeId || doc.id.replace(/^type-/, ''), serviceName: type.name,
      description: `Sample ${type.name} work in ${town.name}: ₹${rate} per hour. A sample listing for testing.`, price: rate, unit: 'per hour', stock: 0,
      phone: `93000000${String(i + 1).padStart(2, '0')}`, whatsapp: `9193000000${String(i + 1).padStart(2, '0')}`, imageUrl: photos[0], images: photos.slice(1),
      pincode: town.pincode, town: town.name, latitude: spot.lat, longitude: spot.lng, active: true, order: 2000 + i, isSample: true,
    });
    serviceListings.push({id, type: type.name, town: town.name, rate});
  }
  out.serviceListings = serviceListings.length;
  log(`Service listings for ${serviceListings.length} service types`);

  // ---- Customers (4).
  const users = [];
  for (const [i, townKey] of ['narsipatnam', 'tuni', 'rajahmundry', 'visakhapatnam'].entries()) {
    const n = i + 1;
    const town = TOWNS[townKey];
    const u = await account(`sample.user${n}@samples.locamarket.test`, `Sample User ${n}`, 'customer');
    await db.collection('users').doc(u.uid).set({name: `Sample User ${n}`, language: 'en', isSample: true, pincode: town.pincode, town: town.name}, {merge: true});
    users.push({n, uid: u.uid, email: u.email, town: town.name});
  }
  out.users = users;
  log('Customers ready');

  // ---- Staff add a vendor (Sample Staff 1, auto-approve ON) and a provider (Sample Staff 2, auto-approve OFF: waits for the admin).
  out.staffAdditions = await staffAdditions(staff, admin, T);

  // ---- Ads: "Ad Sample 1" .. "Ad Sample 10". 1-4 are sent by vendors from the vendor app and approved by the admin with a radius; 5-10
  // are made by the admin. 25 and 50 km circles over the five towns; different timers.
  out.ads = await makeAds(vendors, admin, T);

  // ---- Right Side Ad Boxes 1-12 with sample photos (box 4 already ended, box 8 starts in 5 minutes); box 2 is a vendor's shop ad.
  out.rightBoxes = await makeBoxes(vendors, admin, T);

  // ---- Today's Offers: four item offers (one in each of four towns).
  out.todayOffers = await makeTodayOffers(vendors, library, T);

  out.finishedAt = iso(Date.now());
  fs.writeFileSync(OUT, JSON.stringify(out, null, 1));
  log('Done. Written', OUT);
}

async function staffAdditions(staff, admin, T) {
  const result = {};
  // Staff 1 (auto-approve ON) adds a vendor in Narsipatnam with 3 photos and 2 items (2 photos each).
  const s1 = staff[0];
  const token1 = await signIn(s1.email);
  const add1 = `samplevendor${T}`;
  for (let k = 1; k <= 3; k++) await save(`staffAdditions/${s1.uid}/${add1}/vendor_${k}`, await picture(`Staff Added Vendor ${k === 1 ? '' : `Photo ${k}`}`.trim()));
  for (let item = 1; item <= 2; item++) for (let k = 1; k <= 2; k++) await save(`staffAdditions/${s1.uid}/${add1}/item${item}_${k}`, await picture(`Staff Added Item ${item} Photo ${k}`));
  const spot = near(TOWNS.narsipatnam, 2.1, 0.7);
  result.vendor = await call('submitStaffVendor', {
    additionId: add1, latitude: spot.lat, longitude: spot.lng, gpsAddress: 'Narsipatnam market',
    vendor: {name: 'Sample Staff Shop 1', phone: '9400000001', ownerName: 'Sample Staff Vendor 1', shopCategory: 'Vegetables', address: 'Market Road, Narsipatnam', pincode: '531116', description: 'A shop added by Sample Staff 1.'},
    items: [{libraryItemId: 'sample-lib-tomato', unitType: 'kg', quantity: 1, price: 26, photoCount: 2}, {libraryItemId: 'sample-lib-onion', unitType: 'kg', quantity: 1, price: 38, photoCount: 2}],
  }, token1);
  await mark('staffAdditions', add1);
  // Staff 2 (auto-approve OFF) adds a plumber in Tuni with 3 work photos: it waits for the admin.
  const s2 = staff[1];
  const token2 = await signIn(s2.email);
  const add2 = `sampleprovider${T}`;
  for (let k = 1; k <= 3; k++) await save(`staffAdditions/${s2.uid}/${add2}/work_${k}`, await picture(`Plumbing Sample ${k}`, {sub: 'Sample Work Photo - added by staff'}));
  const spot2 = near(TOWNS.tuni, -0.5, 0.9);
  result.provider = await call('submitStaffProvider', {
    additionId: add2, latitude: spot2.lat, longitude: spot2.lng, serviceTypeId: 'type-plumber', hourlyRate: 260, photoCount: 3,
    provider: {name: 'Sample Staff Plumber 1', phone: '9400000002', address: 'Station Road, Tuni', pincode: '533401'},
  }, token2);
  await mark('staffAdditions', add2);
  log('Staff additions:', JSON.stringify({vendor: result.vendor.status, provider: result.provider.status}));
  return result;
}

const AD_PLAN = [
  // [vendor index (centre), radius km, start offset ms, end offset ms, audience, made by]
  [0, 25, -1 * HOUR, 7 * DAY, 'customers', 'vendor'],
  [1, 50, 0, 3 * DAY, 'customers', 'vendor'],
  [4, 25, 0, 5 * DAY, 'customers', 'vendor'],
  [6, 50, 0, 10 * DAY, 'customers', 'vendor'],
  [8, 25, -3 * DAY, -1 * DAY, 'customers', 'admin'],
  [9, 50, -1 * HOUR, 2 * MIN, 'customers', 'admin'],
  [10, 25, -1 * HOUR, 1 * MIN, 'customers', 'admin'],
  [11, 50, 3 * MIN, 2 * DAY, 'customers', 'admin'],
  [7, 25, 0, 6 * DAY, 'customers,vendors,staff', 'admin'],
  [5, 50, 0, 4 * DAY, 'customers,vendors,staff', 'admin'],
];

async function makeAds(vendors, admin, T) {
  const ads = [];
  for (const [i, [vi, radiusKm, startOff, endOff, audience, by]] of AD_PLAN.entries()) {
    const n = i + 1;
    const v = vendors[vi];
    const title = `Ad Sample ${n}`;
    let adId;
    if (by === 'vendor') {
      // The vendor uploads the ad photo into their own folder and sends it; the admin approves it with a radius.
      const token = await signIn(v.email);
      const imageUrl = await save(`vendorProducts/${v.uid}/ad-sample-${n}.png`, await picture(title, {sub: `${v.shop} - ${v.town} - ${radiusKm} km`}));
      const sent = await call('submitVendorAd', {contentType: 'image', imageUrl, title, text: `${v.shop}, ${v.town}`, package: 'normal', durationDays: Math.max(1, Math.round(endOff / DAY)), tapAction: 'shop', tapValue: v.uid}, token);
      await mark('adSubmissions', sent.submissionId);
      adId = (await call('decideVendorAd', {submissionId: sent.submissionId, approved: true, radiusKm}, admin.token)).adId;
    } else {
      adId = `sample-ad-${n}`;
      const imageUrl = await samplePhoto(title, {sub: `${v.shop} - ${v.town} - ${radiusKm} km`});
      await db.collection('ads').doc(adId).set({
        title, text: `${v.shop}, ${v.town}`, contentType: 'image', imageUrl, status: 'approved', active: true, package: 'normal', rounds: 1, seconds: 5, maxPerDay: 0,
        radiusKm, radiusShopId: v.uid, radiusLat: v.lat, radiusLng: v.lng, tapAction: 'shop', tapValue: v.uid, audience, order: 100 + n, source: 'admin',
      });
      await db.collection('adsPrivate').doc(adId).set({contactPerson: v.shop, phone: v.phone, amount: 0, paid: false, notes: 'Sample ad', isSample: true});
    }
    // The timer (the admin can set and change it in Settings > Right Side Ads): start and end in India time.
    await db.collection('ads').doc(adId).set({startsAt: new Date(T + startOff).toISOString(), endsAt: new Date(T + endOff).toISOString(), audience, isSample: true, order: 100 + n}, {merge: true});
    ads.push({n, adId, title, centre: v.town, shop: v.shop, radiusKm, startsAt: new Date(T + startOff).toISOString(), endsAt: new Date(T + endOff).toISOString(), audience, by, lat: v.lat, lng: v.lng});
    log(`${title} ${adId} ${v.town} ${radiusKm} km by ${by}`);
  }
  return ads;
}

async function makeBoxes(vendors, admin, T) {
  const ref = db.collection('settings').doc('rightAdBoxes');
  const current = (await ref.get()).data() || {};
  const fields = {count: Math.max(15, Number(current.count) || 15)};
  const boxes = [];
  for (let n = 1; n <= 12; n++) {
    if (current[`box${n}Image`]) continue; // never over a real box photo
    fields[`box${n}Image`] = await samplePhoto(`Box Sample ${n}`, {w: 600, h: 480, sub: 'Right Side Ad Box - SAMPLE'});
    fields[`box${n}Sample`] = true;
    if (n === 4) { fields.box4StartsAt = new Date(T - 2 * DAY).toISOString(); fields.box4EndsAt = new Date(T - HOUR).toISOString(); }
    if (n === 8) { fields.box8StartsAt = new Date(T + 5 * MIN).toISOString(); fields.box8EndsAt = new Date(T + 3 * DAY).toISOString(); }
    if (n === 5) fields.box5EndsAt = new Date(T + 4 * MIN).toISOString();
    boxes.push(n);
  }
  await ref.set(fields, {merge: true});
  // Box 2 is a shop ad of Sample Vendor 3 (who ticked "Ad for your shop"): its views count for the vendor.
  const linked = await call('assignRightBoxVendor', {box: 2, vendorId: vendors[2].uid}, admin.token);
  await mark('rightBoxAds', linked.adId);
  log(`Right Side Ad Boxes with sample photos: ${boxes.join(', ')}; box 2 shop ad ${linked.adId}`);
  return {boxes, shopAd: linked.adId, expired: 4, scheduled: 8, endsSoon: 5};
}

async function makeTodayOffers(vendors, library, T) {
  const lib = Object.fromEntries(library.map(l => [l.id, l]));
  const plan = [[3, 'sample-lib-tomato', 22, 1], [4, 'sample-lib-tomato', 24, 2], [6, 'sample-lib-tomato', 29, 3], [8, 'sample-lib-tomato', 30, 4]];
  const offers = [];
  for (const [vi, libId, price, slot] of plan) {
    const v = vendors[vi];
    const product = (await db.collection('products').where('shopId', '==', v.uid).where('libraryItemId', '==', libId).limit(1).get()).docs[0];
    const id = `sample-today-offer-${slot}`;
    await db.collection('promotions').doc(id).set({
      placement: 'offer', slot, productId: product?.id || '', name: lib[libId].name, imageUrl: product?.data().imageUrl || '', offerPrice: price, unit: '1 kg',
      shopId: v.uid, town: v.town, startsAt: new Date(T - HOUR).toISOString(), endsAt: new Date(T + (slot === 4 ? 3 * MIN : 2 * DAY)).toISOString(), active: true, isSample: true,
    });
    offers.push({id, slot, shop: v.shop, town: v.town, price});
  }
  log('Today\'s Offers item offers ready');
  return offers;
}

/// Moves the short timers to start from now again: Ad Sample 6 (ends in 2 min), 7 (ends in 1 min), 8 (starts in 3 min); box 5 (ends in
/// 4 min), box 8 (starts in 5 min); Today's Offer 4 (ends in 3 min).
async function resetTimers(T, out) {
  const ads = (await db.collection('ads').where('isSample', '==', true).get()).docs;
  const byTitle = Object.fromEntries(ads.map(d => [d.data().title, d.ref]));
  const set = async (title, start, end) => { if (byTitle[title]) await byTitle[title].set({startsAt: new Date(T + start).toISOString(), endsAt: new Date(T + end).toISOString()}, {merge: true}); };
  await set('Ad Sample 6', -HOUR, 2 * MIN);
  await set('Ad Sample 7', -HOUR, 1 * MIN);
  await set('Ad Sample 8', 3 * MIN, 2 * DAY);
  await db.collection('settings').doc('rightAdBoxes').set({box5EndsAt: new Date(T + 4 * MIN).toISOString(), box8StartsAt: new Date(T + 5 * MIN).toISOString()}, {merge: true});
  await db.collection('promotions').doc('sample-today-offer-4').set({endsAt: new Date(T + 3 * MIN).toISOString()}, {merge: true});
  out.timersResetAt = new Date(T).toISOString();
  fs.writeFileSync(OUT.replace(/\.json$/, '-timers.json'), JSON.stringify(out, null, 1));
  log('Timers reset from', out.timersResetAt);
}

main().catch(error => { console.error(error); process.exitCode = 1; });
