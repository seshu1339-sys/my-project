// Adds the home-page categories that have built-in photos (assets/category_icons)
// to the live Firestore `categories` collection, if they are not there yet:
// Books, Clothes, Electricals, Fancy, Footwear, Mobiles, Plastics (Electronics
// already exists). Existing categories are never changed or deleted.
//
//   node scripts/add-icon-categories.cjs          # dry run: shows what it would add
//   node scripts/add-icon-categories.cjs --apply  # creates the missing ones
//
// Uses the signed-in Firebase CLI (firebase login); never prints credentials.
// The new categories get no image URL on purpose: the app shows the built-in
// photo until the admin uploads their own in Business Studio.
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const { getProjectDefaultAccount } = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';
const apply = process.argv.includes('--apply');
const WANTED = ['Books', 'Clothes', 'Electricals', 'Electronics', 'Fancy', 'Footwear', 'Mobiles', 'Plastics'];

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({ project, ...account, nonInteractive: true });
  const firestore = new Client({ urlPrefix: 'https://firestore.googleapis.com', auth: true });
  const base = `/v1/projects/${project}/databases/(default)/documents/categories`;
  const existing = (await firestore.get(base, { queryParams: { pageSize: 300 } })).body.documents || [];
  const val = (f) => f && (f.stringValue ?? f.integerValue ?? f.doubleValue);
  const ids = new Set(existing.map((d) => d.name.split('/').pop()));
  const names = new Set(existing.map((d) => String(val((d.fields || {}).name) || '').toLowerCase().replace(/[^a-z0-9]/g, '')));
  let order = Math.max(0, ...existing.map((d) => Number(val((d.fields || {}).order)) || 0));
  for (const name of WANTED) {
    const slug = name.toLowerCase();
    if (ids.has(`cat-${slug}`) || names.has(slug)) { console.log(`exists  ${name}`); continue; }
    order += 1;
    console.log(`${apply ? 'adding ' : 'would add'} ${name} (id cat-${slug}, order ${order})`);
    if (!apply) continue;
    await firestore.post(`${base}?documentId=cat-${slug}`, {
      fields: {
        name: { stringValue: name },
        parentId: { stringValue: '' },
        imageUrl: { stringValue: '' },
        order: { integerValue: String(order) },
        active: { booleanValue: true },
      },
    });
  }
  if (!apply) console.log('Dry run only. Add --apply to create them.');
})().catch((e) => { console.error(e.message || e); process.exit(1); });
