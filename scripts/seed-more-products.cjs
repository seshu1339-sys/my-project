// One-time fix, safe to re-run (fixed ids + updateMask, same convention as
// seed-demo-catalog.cjs). Fills out every category with real products so
// "Featured Products" and the category pages aren't empty/thin, matching the
// reference design's fuller catalog. Every product uses the normal
// `products` schema (price/compareAtPrice/unit/stock/etc.) — nothing special
// — so every field, including price, is editable afterward in the admin
// panel exactly like any other product.
// Run from the repo root: node scripts/seed-more-products.cjs
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
  return {stringValue: String(v)};
}
async function setDoc(firestore, collection, id, data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) { if (v !== undefined) fields[k] = encodeValue(v); }
  const fieldPaths = Object.keys(data).map(k => 'updateMask.fieldPaths=' + encodeURIComponent(k)).join('&');
  await firestore.patch(
    `/v1/projects/${project}/databases/(default)/documents/${collection}/${id}?${fieldPaths}`,
    {fields},
  );
}

const products = [
  // Fruits (previously had none)
  {id: 'prod-apple', name: 'Apple', categoryId: 'cat-fruits', price: 180, compareAtPrice: 210, unit: '1 kg', stock: 80, order: 1, description: 'Crisp, juicy apples.'},
  {id: 'prod-banana', name: 'Banana', categoryId: 'cat-fruits', price: 50, unit: '1 dozen', stock: 100, order: 2, description: 'Ripe and sweet bananas.'},
  {id: 'prod-orange', name: 'Orange', categoryId: 'cat-fruits', price: 90, compareAtPrice: 110, unit: '1 kg', stock: 80, order: 3, description: 'Juicy, tangy oranges.'},
  {id: 'prod-grapes', name: 'Grapes', categoryId: 'cat-fruits', price: 120, unit: '1 kg', stock: 60, order: 4, description: 'Seedless green grapes.'},
  // Rice, Dal & Grains
  {id: 'prod-toor-dal', name: 'Toor Dal', categoryId: 'cat-rice-dal-grains', price: 160, compareAtPrice: 180, unit: '1 kg', stock: 60, order: 1, description: 'Premium split pigeon peas.'},
  {id: 'prod-moong-dal', name: 'Moong Dal', categoryId: 'cat-rice-dal-grains', price: 140, unit: '1 kg', stock: 60, order: 2, description: 'Yellow split moong dal.'},
  {id: 'prod-sona-masoori', name: 'Sona Masoori Rice', categoryId: 'cat-rice-dal-grains', price: 65, unit: '1 kg', stock: 100, order: 3, description: 'Everyday Sona Masoori rice.'},
  {id: 'prod-wheat', name: 'Whole Wheat', categoryId: 'cat-rice-dal-grains', price: 45, unit: '1 kg', stock: 80, order: 4, description: 'Unmilled whole wheat grain.'},
  // Atta, Flours & Sooji
  {id: 'prod-maida', name: 'Maida (Refined Flour)', categoryId: 'cat-atta-flours', price: 50, unit: '1 kg', stock: 50, order: 1, description: 'Fine refined flour.'},
  {id: 'prod-besan', name: 'Besan (Gram Flour)', categoryId: 'cat-atta-flours', price: 90, unit: '1 kg', stock: 50, order: 2, description: 'Roasted gram flour.'},
  {id: 'prod-rava', name: 'Rava / Sooji', categoryId: 'cat-atta-flours', price: 55, unit: '1 kg', stock: 50, order: 3, description: 'Fine semolina for breakfast dishes.'},
  // Cooking Oils & Ghee
  {id: 'prod-groundnut-oil', name: 'Groundnut Oil', categoryId: 'cat-cooking-oils-ghee', price: 195, compareAtPrice: 215, unit: '1 L', stock: 50, order: 1, description: 'Cold-pressed groundnut oil.'},
  {id: 'prod-ghee', name: 'Pure Ghee', categoryId: 'cat-cooking-oils-ghee', price: 620, compareAtPrice: 680, unit: '1 kg', stock: 30, order: 2, description: 'Traditional clarified butter.'},
  {id: 'prod-coconut-oil', name: 'Coconut Oil', categoryId: 'cat-cooking-oils-ghee', price: 210, unit: '1 L', stock: 40, order: 3, description: 'Pure coconut cooking oil.'},
  // Masalas & Spices
  {id: 'prod-turmeric', name: 'Turmeric Powder', categoryId: 'cat-masalas-spices', price: 45, unit: '100 g', stock: 80, order: 1, description: 'Pure ground turmeric.'},
  {id: 'prod-chilli-powder', name: 'Chilli Powder', categoryId: 'cat-masalas-spices', price: 60, unit: '100 g', stock: 80, order: 2, description: 'Hot, fresh red chilli powder.'},
  {id: 'prod-garam-masala', name: 'Garam Masala', categoryId: 'cat-masalas-spices', price: 70, unit: '100 g', stock: 60, order: 3, description: 'Aromatic blended spice mix.'},
  {id: 'prod-coriander-powder', name: 'Coriander Powder', categoryId: 'cat-masalas-spices', price: 40, unit: '100 g', stock: 60, order: 4, description: 'Freshly ground coriander.'},
  // More Snacks & Beverages
  {id: 'prod-biscuits', name: 'Glucose Biscuits', categoryId: 'cat-snacks-beverages', price: 30, unit: '1 pack', stock: 100, order: 2, description: 'Classic glucose biscuits.'},
  {id: 'prod-tea-powder', name: 'Tea Powder', categoryId: 'cat-snacks-beverages', price: 140, unit: '250 g', stock: 60, order: 3, description: 'Strong, aromatic tea powder.'},
  {id: 'prod-coffee', name: 'Filter Coffee Powder', categoryId: 'cat-snacks-beverages', price: 180, unit: '200 g', stock: 50, order: 4, description: 'South Indian filter coffee blend.'},
  // More Personal Care
  {id: 'prod-shampoo', name: 'Shampoo', categoryId: 'cat-personal-care', price: 150, unit: '180 ml', stock: 60, order: 2, description: 'Gentle daily-use shampoo.'},
  {id: 'prod-toothpaste', name: 'Toothpaste', categoryId: 'cat-personal-care', price: 55, unit: '100 g', stock: 100, order: 3, description: 'Cavity-protection toothpaste.'},
  // More Household Essentials
  {id: 'prod-dishwash-bar', name: 'Dishwash Bar', categoryId: 'cat-household', price: 25, unit: 'each', stock: 100, order: 2, description: 'Grease-cutting dishwash bar.'},
  {id: 'prod-phenyl', name: 'Phenyl / Floor Cleaner', categoryId: 'cat-household', price: 60, unit: '500 ml', stock: 60, order: 3, description: 'Disinfectant floor cleaner.'},
  // Baby & Kids (previously had none)
  {id: 'prod-baby-wipes', name: 'Baby Wipes', categoryId: 'cat-baby-kids', price: 120, unit: '1 pack', stock: 50, order: 1, description: 'Soft, gentle baby wipes.'},
  {id: 'prod-diapers', name: 'Diapers', categoryId: 'cat-baby-kids', price: 450, compareAtPrice: 500, unit: '1 pack', stock: 40, order: 2, description: 'Comfortable, absorbent diapers.'},
  {id: 'prod-baby-soap', name: 'Baby Soap', categoryId: 'cat-baby-kids', price: 80, unit: 'each', stock: 60, order: 3, description: 'Mild soap for baby skin.'},
  // More Dairy & Bakery
  {id: 'prod-paneer', name: 'Paneer', categoryId: 'cat-dairy-bakery', price: 90, unit: '200 g', stock: 40, order: 3, description: 'Fresh soft paneer.'},
  {id: 'prod-curd', name: 'Curd', categoryId: 'cat-dairy-bakery', price: 40, unit: '400 g', stock: 60, order: 4, description: 'Fresh, thick curd.'},
];

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  for (const p of products) {
    const {id, ...data} = p;
    await setDoc(firestore, 'products', id, data);
    console.log(id + ': seeded.');
  }
  console.log(`Done: ${products.length} products seeded. Reload the site to see it.`);
})().catch(error => { console.error(error.message); process.exitCode = 1; });
