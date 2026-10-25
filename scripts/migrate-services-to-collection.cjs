// Moves services into their own Firestore collection ("services").
//
//   node scripts/migrate-services-to-collection.cjs                    only reads and prints the counts (changes nothing)
//   node scripts/migrate-services-to-collection.cjs --apply            COPIES: every products record of kind "service" -> services (same id,
//                                                                      same fields), and the 30 service types of assets/services/services_list.json
//                                                                      -> services/type-<id> (kind "serviceType"). Nothing is deleted.
//   node scripts/migrate-services-to-collection.cjs --delete-originals deletes the service records from products, but only those whose
//                                                                      copy in services is identical. Run it after the new app is live.
//
// Safe to run again: a record already in services is left as it is. Take a backup first (scripts/backup-firestore.cjs).
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));

const project = 'e-commerce-app-a3897';
const apply = process.argv.includes('--apply');
const deleteOriginals = process.argv.includes('--delete-originals');
const base = `/v1/projects/${project}/databases/(default)/documents`;
const str = v => ({stringValue: String(v)});
const int = v => ({integerValue: String(v)});

async function listAll(api, collection) {
  const docs = [];
  let token;
  do {
    const res = await api.get(`${base}/${collection}`, {queryParams: {pageSize: 300, ...(token ? {pageToken: token} : {})}});
    docs.push(...(res.body.documents || []));
    token = res.body.nextPageToken;
  } while (token);
  return docs;
}
const idOf = doc => doc.name.split('/').pop();
const nameOf = doc => doc.fields?.name?.stringValue || idOf(doc);
// Same fields whatever order the server lists them in.
const canon = v => (Array.isArray(v) ? v.map(canon) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, canon(v[k])])) : v);
const same = (a, b) => JSON.stringify(canon(a || {})) === JSON.stringify(canon(b || {}));

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const api = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  const types = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'assets', 'services', 'services_list.json'), 'utf8'));
  const typeDocs = types.map(t => ({id: `type-${t.id}`, fields: {kind: str('serviceType'), typeId: str(t.id), name: str(t.display_name), imageFileName: str(t.image_file_name), order: int(t.display_order), active: {booleanValue: true}}}));

  const products = await listAll(api, 'products');
  const serviceInProducts = products.filter(d => d.fields?.kind?.stringValue === 'service');
  let services = await listAll(api, 'services').catch(() => []);
  const listings = services.filter(d => d.fields?.kind?.stringValue !== 'serviceType');
  const typesIn = services.filter(d => d.fields?.kind?.stringValue === 'serviceType');
  console.log('BEFORE');
  console.log(`  products (all records):                    ${products.length}`);
  console.log(`  service records still in products:         ${serviceInProducts.length}   ${serviceInProducts.map(nameOf).join(' | ')}`);
  console.log(`  service types in the app file:             ${typeDocs.length}`);
  console.log(`  services collection: listings ${listings.length}, types ${typesIn.length}, total ${services.length}`);
  console.log(`  expected in services after the copy:       ${serviceInProducts.length + typeDocs.length}`);

  const put = async (id, fields) => {
    try {
      await api.patch(`${base}/services/${id}`, {fields}, {queryParams: {'currentDocument.exists': 'false'}});
      return true;
    } catch (e) {
      if (/ALREADY_EXISTS|already exists|409|FAILED_PRECONDITION|412/i.test(String(e.message) + String(e.status))) return false;
      throw e;
    }
  };

  if (apply) {
    let copied = 0, kept = 0;
    for (const doc of serviceInProducts) (await put(idOf(doc), doc.fields)) ? copied++ : kept++;
    for (const t of typeDocs) (await put(t.id, t.fields)) ? copied++ : kept++;
    console.log(`COPIED ${copied} records into services (${kept} were already there and were left as they are)`);
    services = await listAll(api, 'services');
  }

  if (apply || deleteOriginals) {
    const after = services;
    const afterListings = after.filter(d => d.fields?.kind?.stringValue !== 'serviceType');
    const afterTypes = after.filter(d => d.fields?.kind?.stringValue === 'serviceType');
    console.log('AFTER');
    console.log(`  services collection: listings ${afterListings.length}, types ${afterTypes.length}, total ${after.length}`);
    const byId = new Map(after.map(d => [idOf(d), d]));
    const missing = [], different = [];
    for (const doc of serviceInProducts) {
      const copy = byId.get(idOf(doc));
      if (!copy) missing.push(nameOf(doc));
      else if (!same(copy.fields, doc.fields)) different.push(nameOf(doc));
    }
    for (const t of typeDocs) if (!byId.has(t.id)) missing.push(t.id);
    console.log(`  missing after the copy: ${missing.length}${missing.length ? '  ' + missing.join(', ') : ''}`);
    console.log(`  copies that differ from the original: ${different.length}${different.length ? '  ' + different.join(', ') : ''}`);
    console.log(missing.length === 0 && different.length === 0 ? '  CHECK PASSED: nothing is missing' : '  CHECK FAILED');
    if (missing.length || different.length) process.exitCode = 1;

    if (deleteOriginals) {
      if (missing.length || different.length) throw Error('Not deleting anything: the copies are not all in place.');
      let deleted = 0;
      for (const doc of serviceInProducts) {
        await api.delete(`${base}/products/${idOf(doc)}`);
        deleted++;
      }
      const left = (await listAll(api, 'products')).filter(d => d.fields?.kind?.stringValue === 'service').length;
      console.log(`DELETED ${deleted} service records from products. Service records left in products: ${left}`);
    }
  } else {
    console.log('Nothing was changed. Run with --apply to copy.');
  }
})().catch(e => { console.error('Failed:', e.message); process.exit(1); });
