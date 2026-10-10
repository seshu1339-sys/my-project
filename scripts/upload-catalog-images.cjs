// One-time fix, safe to re-run. Uploads every file from the user's
// "Locamarket HD Images" desktop folder to Firebase Storage under
// catalog/<docId>.png (storage.rules already makes that path public-read —
// see the `match /catalog/{file}` block), then writes the resulting public
// download URL into that product/category's Firestore `imageUrl` field.
// Run from the repo root: node scripts/upload-catalog-images.cjs
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';
const bucket = 'e-commerce-app-a3897.firebasestorage.app';

const root = 'C:\\Users\\Lappy\\Desktop\\Locamarket HD Images';

// [local file relative to root, firestore collection, doc id]
const items = [
  ['Category Images\\Fresh & Vegetables.png', 'categories', 'cat-vegetables'],
  ['Category Images\\Fruits.png', 'categories', 'cat-fruits'],
  ['Category Images\\Dairy & Bakery.png', 'categories', 'cat-dairy-bakery'],
  ['Category Images\\Grocery & Staples.png', 'categories', 'cat-grocery-staples'],
  ['Category Images\\Snacks & Beverages.png', 'categories', 'cat-snacks-beverages'],
  ['Category Images\\Personal Care.png', 'categories', 'cat-personal-care'],
  ['Category Images\\Household Essentials.png', 'categories', 'cat-household'],
  ['Category Images\\Rice, Dal & Grains.png', 'categories', 'cat-rice-dal-grains'],
  ['Category Images\\Atta, Flours & Sooji.png', 'categories', 'cat-atta-flours'],
  ['Category Images\\Cooking Oils & Ghee.png', 'categories', 'cat-cooking-oils-ghee'],
  ['Category Images\\Masalas & Spices.png', 'categories', 'cat-masalas-spices'],
  ['Category Images\\Baby & Kids.png', 'categories', 'cat-baby-kids'],
  ['Product Images\\Vegetables\\Fresh Tomato.png', 'products', 'prod-tomato'],
  ['Product Images\\Vegetables\\Onion.png', 'products', 'prod-onion'],
  ['Product Images\\Vegetables\\Potato.png', 'products', 'prod-potato'],
  ['Product Images\\Vegetables\\Capsicum.png', 'products', 'prod-capsicum'],
  ['Product Images\\Fruits\\Apple.png', 'products', 'prod-apple'],
  ['Product Images\\Fruits\\Banana.png', 'products', 'prod-banana'],
  ['Product Images\\Fruits\\Orange.png', 'products', 'prod-orange'],
  ['Product Images\\Fruits\\Grapes.png', 'products', 'prod-grapes'],
  ['Product Images\\Grocery & Staples\\India Gate Basmati Rice.png', 'products', 'prod-basmati-rice'],
  ['Product Images\\Grocery & Staples\\Aashirvaad Atta.png', 'products', 'prod-atta'],
  ['Product Images\\Grocery & Staples\\Freedom Sunflower Oil.png', 'products', 'prod-sunflower-oil'],
  ['Product Images\\Dairy & Bakery\\Milk.png', 'products', 'prod-milk'],
  ['Product Images\\Dairy & Bakery\\Fresh Bread.png', 'products', 'prod-bread'],
  ['Product Images\\Dairy & Bakery\\Paneer.png', 'products', 'prod-paneer'],
  ['Product Images\\Dairy & Bakery\\Curd.png', 'products', 'prod-curd'],
  ['Product Images\\Snacks & Beverages\\Lays Chips.png', 'products', 'prod-chips'],
  ['Product Images\\Snacks & Beverages\\Glucose Biscuits.png', 'products', 'prod-biscuits'],
  ['Product Images\\Snacks & Beverages\\Tea Powder.png', 'products', 'prod-tea-powder'],
  ['Product Images\\Snacks & Beverages\\Filter Coffee Powder.png', 'products', 'prod-coffee'],
  ['Product Images\\Personal Care\\Dove Soap.png', 'products', 'prod-soap'],
  ['Product Images\\Personal Care\\Shampoo.png', 'products', 'prod-shampoo'],
  ['Product Images\\Personal Care\\Toothpaste.png', 'products', 'prod-toothpaste'],
  ['Product Images\\Household\\Surf Excel Detergent.png', 'products', 'prod-detergent'],
  ['Product Images\\Household\\Dishwash Bar.png', 'products', 'prod-dishwash-bar'],
  ['Product Images\\Household\\Phenyl - Floor Cleaner.png', 'products', 'prod-phenyl'],
  ['Product Images\\Rice, Dal & Grains\\Toor Dal.png', 'products', 'prod-toor-dal'],
  ['Product Images\\Rice, Dal & Grains\\Moong Dal.png', 'products', 'prod-moong-dal'],
  ['Product Images\\Rice, Dal & Grains\\Sona Masoori Rice.png', 'products', 'prod-sona-masoori'],
  ['Product Images\\Rice, Dal & Grains\\Whole Wheat.png', 'products', 'prod-wheat'],
  ['Product Images\\Atta, Flours & Sooji\\Maida.png', 'products', 'prod-maida'],
  ['Product Images\\Atta, Flours & Sooji\\Besan.png', 'products', 'prod-besan'],
  ['Product Images\\Atta, Flours & Sooji\\Rava - Sooji.png', 'products', 'prod-rava'],
  ['Product Images\\Cooking Oils & Ghee\\Groundnut Oil.png', 'products', 'prod-groundnut-oil'],
  ['Product Images\\Cooking Oils & Ghee\\Pure Ghee.png', 'products', 'prod-ghee'],
  ['Product Images\\Cooking Oils & Ghee\\Coconut Oil.png', 'products', 'prod-coconut-oil'],
  ['Product Images\\Masalas & Spices\\Turmeric Powder.png', 'products', 'prod-turmeric'],
  ['Product Images\\Masalas & Spices\\Chilli Powder.png', 'products', 'prod-chilli-powder'],
  ['Product Images\\Masalas & Spices\\Garam Masala.png', 'products', 'prod-garam-masala'],
  ['Product Images\\Masalas & Spices\\Coriander Powder.png', 'products', 'prod-coriander-powder'],
  ['Product Images\\Baby & Kids\\Baby Wipes.png', 'products', 'prod-baby-wipes'],
  ['Product Images\\Baby & Kids\\Diapers.png', 'products', 'prod-diapers'],
  ['Product Images\\Baby & Kids\\Baby Soap.png', 'products', 'prod-baby-soap'],
];

async function uploadToStorage(storage, objectName, fileBuffer) {
  const res = await storage.request({
    method: 'POST',
    path: `/upload/storage/v1/b/${encodeURIComponent(bucket)}/o`,
    queryParams: {uploadType: 'media', name: objectName},
    headers: new Headers({'Content-Type': 'image/png'}),
    body: fileBuffer,
  });
  if (res.status >= 400) {
    throw new Error(`Storage upload failed (${res.status}): ${JSON.stringify(res.body)}`);
  }
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(objectName)}?alt=media`;
}

async function setImageUrl(firestore, collection, id, imageUrl) {
  await firestore.patch(
    `/v1/projects/${project}/databases/(default)/documents/${collection}/${id}?updateMask.fieldPaths=imageUrl`,
    {fields: {imageUrl: {stringValue: imageUrl}}},
  );
}

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});
  const storage = new Client({urlPrefix: 'https://storage.googleapis.com', auth: true});

  let ok = 0, failed = 0;
  for (const [relPath, collection, id] of items) {
    const fullPath = path.join(root, relPath);
    if (!fs.existsSync(fullPath)) {
      console.log(id, '-> MISSING FILE:', fullPath);
      failed++;
      continue;
    }
    try {
      const bytes = fs.readFileSync(fullPath);
      const objectName = `catalog/${id}.png`;
      const imageUrl = await uploadToStorage(storage, objectName, bytes);
      await setImageUrl(firestore, collection, id, imageUrl);
      console.log(id, '-> OK', imageUrl);
      ok++;
    } catch (error) {
      console.log(id, '-> FAILED:', error.message);
      failed++;
    }
  }
  console.log(`\nDone: ${ok} uploaded and linked, ${failed} failed. Reload the site to see it.`);
})().catch((error) => { console.error(error.message); process.exitCode = 1; });
