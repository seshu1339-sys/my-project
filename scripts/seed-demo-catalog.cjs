// One-time helper: seeds realistic sample categories/products/services/shops
// into production Firestore, matching the reference homepage design (grocery
// marketplace with categories, featured products, popular services, nearby
// shops). Run once from the repo root:
//   node scripts/seed-demo-catalog.cjs
// Safe to re-run — every document uses a fixed id and this script always
// writes the SAME fields it declares below (via updateMask), so re-running it
// only refreshes these exact fields, never touches anything else on the
// document and never creates duplicates. Edit the arrays below (names,
// prices, shop details) before running if you want different starting data,
// or just use this as a one-time starting point and edit everything
// afterwards in the admin panel as usual.
'use strict';
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';

function encodeValue(v) {
  if (v === null || v === undefined) return {nullValue: null};
  if (typeof v === 'string') return {stringValue: v};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'number') return Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v};
  if (Array.isArray(v)) return {arrayValue: {values: v.map(encodeValue)}};
  if (typeof v === 'object') return {mapValue: {fields: encodeFields(v)}};
  return {stringValue: String(v)};
}
function encodeFields(obj) {
  const out = {};
  for (const [k, val] of Object.entries(obj)) { if (val !== undefined) out[k] = encodeValue(val); }
  return out;
}
async function setDoc(firestore, collection, id, data) {
  const fieldPaths = Object.keys(data).map(k => 'updateMask.fieldPaths=' + encodeURIComponent(k)).join('&');
  await firestore.patch(
    `/v1/projects/${project}/databases/(default)/documents/${collection}/${id}?${fieldPaths}`,
    {fields: encodeFields(data)},
  );
}

const categories = [
  {id: 'cat-vegetables', name: 'Fresh & Vegetables', order: 1},
  {id: 'cat-fruits', name: 'Fruits', order: 2},
  {id: 'cat-dairy-bakery', name: 'Dairy & Bakery', order: 3},
  {id: 'cat-grocery-staples', name: 'Grocery & Staples', order: 4},
  {id: 'cat-snacks-beverages', name: 'Snacks & Beverages', order: 5},
  {id: 'cat-personal-care', name: 'Personal Care', order: 6},
  {id: 'cat-household', name: 'Household Essentials', order: 7},
];

const products = [
  {id: 'prod-tomato', name: 'Fresh Tomato', categoryId: 'cat-vegetables', price: 25, compareAtPrice: 32, unit: '1 kg', stock: 100, order: 1, description: 'Farm-fresh, hand-picked tomatoes.'},
  {id: 'prod-onion', name: 'Onion', categoryId: 'cat-vegetables', price: 28, compareAtPrice: 34, unit: '1 kg', stock: 100, order: 2, description: 'Locally sourced onions.'},
  {id: 'prod-potato', name: 'Potato', categoryId: 'cat-vegetables', price: 22, compareAtPrice: 26, unit: '1 kg', stock: 100, order: 3, description: 'Fresh potatoes.'},
  {id: 'prod-capsicum', name: 'Capsicum', categoryId: 'cat-vegetables', price: 20, unit: '1 kg', stock: 80, order: 4, description: 'Crisp green capsicum.'},
  {id: 'prod-basmati-rice', name: 'India Gate Basmati Rice', categoryId: 'cat-grocery-staples', price: 670, compareAtPrice: 760, unit: '5 kg', stock: 50, order: 5, description: 'Premium long-grain basmati rice.'},
  {id: 'prod-atta', name: 'Aashirvaad Atta', categoryId: 'cat-grocery-staples', price: 235, compareAtPrice: 260, unit: '5 kg', stock: 50, order: 6, description: 'Whole wheat atta.'},
  {id: 'prod-sunflower-oil', name: 'Freedom Sunflower Oil', categoryId: 'cat-grocery-staples', price: 165, compareAtPrice: 180, unit: '1 L', stock: 50, order: 7, description: 'Refined sunflower oil.'},
  {id: 'prod-milk', name: 'Milk', categoryId: 'cat-dairy-bakery', price: 58, unit: '1 L', stock: 100, order: 8, description: 'Fresh pasteurized milk.'},
  {id: 'prod-bread', name: 'Fresh Bread', categoryId: 'cat-dairy-bakery', price: 40, unit: '400 g', stock: 50, order: 9, description: 'Soft white bread loaf.'},
  {id: 'prod-chips', name: 'Lays Chips', categoryId: 'cat-snacks-beverages', price: 20, unit: '52 g', stock: 100, order: 10, description: 'Classic salted potato chips.'},
  {id: 'prod-soap', name: 'Dove Soap', categoryId: 'cat-personal-care', price: 45, unit: 'each', stock: 100, order: 11, description: 'Moisturizing beauty bar.'},
  {id: 'prod-detergent', name: 'Surf Excel Detergent', categoryId: 'cat-household', price: 120, unit: '1 kg', stock: 50, order: 12, description: 'Powerful stain-removal detergent.'},
];

const services = [
  {id: 'svc-plumbing', name: 'Plumbing Visit', kind: 'service', price: 100, unit: 'per visit', stock: 999, order: 1, description: 'Home plumbing repair and installation.'},
  {id: 'svc-electrician', name: 'Electrician Visit', kind: 'service', price: 200, unit: 'per visit', stock: 999, order: 2, description: 'Electrical repair and wiring work.'},
  {id: 'svc-mason', name: 'Mason Service', kind: 'service', price: 500, unit: 'per visit', stock: 999, order: 3, description: 'Masonry and construction work.'},
  {id: 'svc-labor', name: 'Labor (On Demand)', kind: 'service', price: 300, unit: 'per day', stock: 999, order: 4, description: 'General labor for home/shifting tasks.'},
  {id: 'svc-transport', name: 'Transport (Mini Truck / Load)', kind: 'service', price: 400, unit: 'per trip', stock: 999, order: 5, description: 'Mini truck for local transport and deliveries.'},
];

// Right-side rail boxes (merged into one column by wireframe_home.dart,
// 'ad' and 'box' placements both qualify) — matches the reference design's
// "Big Savings Everyday" / "Home Services At Your Doorstep" rail.
const promotions = [
  {id: 'promo-big-savings', name: 'Big Savings Everyday', description: 'Up to 50% OFF', placement: 'ad', order: 1, width: 260, height: 220, backgroundColor: '#16a34a', textColor: '#ffffff'},
  {id: 'promo-home-services', name: 'Home Services At Your Doorstep', description: 'Plumbing · Electrician · Mason · Labor · Transport', placement: 'box', order: 2, width: 260, height: 220, backgroundColor: '#2563eb', textColor: '#ffffff'},
];

const shops = [
  {id: 'shop-venkateswara', name: 'Sri Venkateswara Vegetables', description: 'Fresh vegetables and fruits daily.', address: 'Main Road, Narsipatnam', phone: '+919000000001', pincode: '531116', latitude: 17.6670, longitude: 82.6160, radiusKm: 5, order: 1},
  {id: 'shop-ramu-kirana', name: 'Ramu Kirana Store', description: 'Daily groceries and staples.', address: 'Bazar Street, Narsipatnam', phone: '+919000000002', pincode: '531116', latitude: 17.6700, longitude: 82.6200, radiusKm: 5, order: 2},
  {id: 'shop-vijaya-dairy', name: 'Vijaya Dairy', description: 'Fresh milk and dairy products.', address: 'Temple Street, Narsipatnam', phone: '+919000000003', pincode: '531116', latitude: 17.6650, longitude: 82.6100, radiusKm: 5, order: 3},
  {id: 'shop-suma-fresh', name: 'Suma Fresh Mart', description: 'Supermarket for all daily needs.', address: 'Station Road, Narsipatnam', phone: '+919000000004', pincode: '531116', latitude: 17.6600, longitude: 82.6250, radiusKm: 5, order: 4},
  {id: 'shop-local-bakery', name: 'Local Bakery', description: 'Fresh bread and bakery items.', address: 'Market Street, Narsipatnam', phone: '+919000000005', pincode: '531116', latitude: 17.6720, longitude: 82.6180, radiusKm: 5, order: 5},
];

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  for (const c of categories) { const {id, ...data} = c; await setDoc(firestore, 'categories', id, data); }
  console.log('categories done:', categories.length);
  for (const p of [...products, ...services]) { const {id, ...data} = p; await setDoc(firestore, 'products', id, data); }
  console.log('products+services done:', products.length + services.length);
  for (const s of shops) { const {id, ...data} = s; await setDoc(firestore, 'shops', id, data); }
  console.log('shops done:', shops.length);
  for (const p of promotions) { const {id, ...data} = p; await setDoc(firestore, 'promotions', id, data); }
  console.log('promotions done:', promotions.length);
  console.log('All done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
