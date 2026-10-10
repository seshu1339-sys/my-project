// One-time fix, safe to re-run. Looks up a real, licensed photo for every
// product and category from Pexels (free stock-photo API, all photos free
// for commercial use under the Pexels License) and writes it to that
// document's `imageUrl` field. Needs a free Pexels API key — sign up at
// https://www.pexels.com/api/ (instant, no cost), then run:
//
//   $env:PEXELS_API_KEY = "your-key-here"
//   node scripts/fetch-and-seed-product-images.cjs
//
// The key only lives in your own shell session's environment variable —
// it's never pasted into chat or committed anywhere.
'use strict';
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';

const PEXELS_KEY = process.env.PEXELS_API_KEY;
if (!PEXELS_KEY) {
  console.error('Set PEXELS_API_KEY first, e.g.:\n  $env:PEXELS_API_KEY = "your-key-here"\n  node scripts/fetch-and-seed-product-images.cjs');
  process.exit(1);
}

// [firestore id, collection, search query]
const items = [
  ['cat-vegetables', 'categories', 'fresh vegetables'],
  ['cat-fruits', 'categories', 'fresh fruits'],
  ['cat-dairy-bakery', 'categories', 'milk and bread'],
  ['cat-grocery-staples', 'categories', 'rice and grocery'],
  ['cat-snacks-beverages', 'categories', 'snacks and chips'],
  ['cat-personal-care', 'categories', 'soap and shampoo'],
  ['cat-household', 'categories', 'cleaning supplies'],
  ['cat-rice-dal-grains', 'categories', 'rice and lentils'],
  ['cat-atta-flours', 'categories', 'wheat flour'],
  ['cat-cooking-oils-ghee', 'categories', 'cooking oil bottle'],
  ['cat-masalas-spices', 'categories', 'indian spices'],
  ['cat-baby-kids', 'categories', 'baby products'],
  ['prod-tomato', 'products', 'fresh tomatoes'],
  ['prod-onion', 'products', 'red onions'],
  ['prod-potato', 'products', 'potatoes'],
  ['prod-capsicum', 'products', 'green bell pepper'],
  ['prod-basmati-rice', 'products', 'rice bag'],
  ['prod-atta', 'products', 'wheat flour bag'],
  ['prod-sunflower-oil', 'products', 'sunflower oil bottle'],
  ['prod-milk', 'products', 'milk bottle'],
  ['prod-bread', 'products', 'loaf of bread'],
  ['prod-chips', 'products', 'potato chips'],
  ['prod-soap', 'products', 'bar of soap'],
  ['prod-detergent', 'products', 'laundry detergent'],
  ['prod-apple', 'products', 'red apples'],
  ['prod-banana', 'products', 'bananas'],
  ['prod-orange', 'products', 'oranges fruit'],
  ['prod-grapes', 'products', 'green grapes'],
  ['prod-toor-dal', 'products', 'yellow lentils dal'],
  ['prod-moong-dal', 'products', 'green lentils'],
  ['prod-sona-masoori', 'products', 'white rice'],
  ['prod-wheat', 'products', 'wheat grain'],
  ['prod-maida', 'products', 'white flour'],
  ['prod-besan', 'products', 'gram flour'],
  ['prod-rava', 'products', 'semolina'],
  ['prod-groundnut-oil', 'products', 'peanut oil bottle'],
  ['prod-ghee', 'products', 'ghee jar'],
  ['prod-coconut-oil', 'products', 'coconut oil bottle'],
  ['prod-turmeric', 'products', 'turmeric powder'],
  ['prod-chilli-powder', 'products', 'red chilli powder'],
  ['prod-garam-masala', 'products', 'spice powder'],
  ['prod-coriander-powder', 'products', 'coriander powder'],
  ['prod-biscuits', 'products', 'biscuits cookies'],
  ['prod-tea-powder', 'products', 'tea leaves'],
  ['prod-coffee', 'products', 'coffee powder'],
  ['prod-shampoo', 'products', 'shampoo bottle'],
  ['prod-toothpaste', 'products', 'toothpaste tube'],
  ['prod-dishwash-bar', 'products', 'dish soap'],
  ['prod-phenyl', 'products', 'floor cleaner bottle'],
  ['prod-baby-wipes', 'products', 'baby wipes'],
  ['prod-diapers', 'products', 'diapers'],
  ['prod-baby-soap', 'products', 'baby soap'],
  ['prod-paneer', 'products', 'paneer cheese'],
  ['prod-curd', 'products', 'yogurt bowl'],
];

async function searchPexels(query) {
  const res = await fetch(`https://api.pexels.com/v1/search?query=${encodeURIComponent(query)}&per_page=1&orientation=square`, {
    headers: {Authorization: PEXELS_KEY},
  });
  if (!res.ok) {
    if (res.status === 429) throw new Error('Pexels rate limit hit — wait a minute and re-run (safe to re-run, already-set images are skipped... actually this script always overwrites; just re-run later).');
    return null;
  }
  const data = await res.json();
  const photo = data.photos?.[0];
  return photo ? (photo.src.large || photo.src.medium) : null;
}

function encodeValue(v) { return {stringValue: v}; }
async function setImageUrl(firestore, collection, id, imageUrl) {
  await firestore.patch(
    `/v1/projects/${project}/databases/(default)/documents/${collection}/${id}?updateMask.fieldPaths=imageUrl`,
    {fields: {imageUrl: encodeValue(imageUrl)}},
  );
}

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  let ok = 0, miss = 0;
  for (const [id, collection, query] of items) {
    const url = await searchPexels(query);
    if (!url) {
      console.log(id, '-> no Pexels result for "' + query + '", skipped');
      miss++;
      continue;
    }
    await setImageUrl(firestore, collection, id, url);
    console.log(id, '->', url);
    ok++;
    await new Promise((r) => setTimeout(r, 250));
  }
  console.log(`\nDone: ${ok} images set, ${miss} skipped (no result). Reload the site to see it.`);
})().catch((error) => { console.error(error.message); process.exitCode = 1; });
