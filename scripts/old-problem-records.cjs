#!/usr/bin/env node
// Cost cuts part 3 (owner, 18 Nov 2026, answer 3b): the problem records the version before 18 Nov 2026 made one per person or per time,
// and the screenshots it kept in Firestore and in the Mumbai bucket. Testing had not really started, so the owner wants them deleted
// ONCE after the deploy, but only after seeing the count and saying OK.
//
//   node scripts/old-problem-records.cjs            COUNT only (changes nothing)
//   node scripts/old-problem-records.cjs --delete   delete them (only after the owner's OK on the count)
//
// What it counts / deletes:
//   appCases/*                      one record per time a problem happened (no longer written)
//   appShots/*                      automatic screenshots in Firestore (now in the US bucket)
//   appProblems/*/who/*             one record per person (the people are now counted inside the problem record)
//   supportShots/*                  AI Support screenshots in Firestore (now in the US bucket)
//   supportTickets/* without members  tickets of the old shape, one per person (now one ticket per problem)
//   problemReports/* files in the Mumbai bucket (e-commerce-app-a3897.firebasestorage.app): the report screenshots; the report text
//                                   stays, only its screenshotPath is cleared
// Firebase sign-in: the firebase CLI's login (as scripts/backup-firestore.cjs); the bucket listing uses gcloud.
'use strict';
const path = require('node:path');
const {execSync} = require('node:child_process');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));

const project = 'e-commerce-app-a3897';
const mumbai = 'e-commerce-app-a3897.firebasestorage.app';
const remove = process.argv.includes('--delete');
const base = `/v1/projects/${project}/databases/(default)/documents`;

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const api = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  async function list(parent, collection, mask = ['__name__']) {
    const docs = [];
    let token;
    do {
      const res = await api.get(`${parent}/${collection}`, {queryParams: {pageSize: 300, 'mask.fieldPaths': mask, ...(token ? {pageToken: token} : {})}});
      docs.push(...(res.body.documents || []));
      token = res.body.nextPageToken;
    } while (token);
    return docs;
  }
  const rel = name => name.split('/documents/')[1];

  const found = {};
  found.appCases = await list(base, 'appCases');
  found.appShots = await list(base, 'appShots');
  found.who = [];
  for (const p of await list(base, 'appProblems')) found.who.push(...await list(`${base}/${rel(p.name)}`, 'who'));
  found.supportShots = await list(base, 'supportShots');
  found.oldSupportTickets = (await list(base, 'supportTickets', ['members', 'status'])).filter(d => !d.fields?.members);
  const reports = (await list(base, 'problemReports', ['screenshotPath'])).filter(d => String(d.fields?.screenshotPath?.stringValue || '').startsWith('problemReports/'));
  let files = [];
  try {
    files = execSync(`gcloud storage ls "gs://${mumbai}/problemReports/**" --project=${project}`, {encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']})
      .split(/\r?\n/).map(s => s.trim()).filter(s => s.startsWith('gs://'));
  } catch (e) {
    if (!/matched no objects|One or more URLs matched no objects/i.test(String(e.stderr || e.message))) throw e;
  }

  console.log('Old problem records (before 18 Nov 2026):');
  console.log(`  appCases (one per time)            ${found.appCases.length}`);
  console.log(`  appShots (screenshots, Firestore)   ${found.appShots.length}`);
  console.log(`  appProblems/*/who (one per person)  ${found.who.length}`);
  console.log(`  supportShots (screenshots)          ${found.supportShots.length}`);
  console.log(`  supportTickets of the old shape     ${found.oldSupportTickets.length}`);
  console.log(`  Mumbai bucket problemReports/ files ${files.length} (reports pointing at them: ${reports.length})`);
  if (!remove) {
    console.log('\nNothing was changed. Run again with --delete only after the owner says OK.');
    return;
  }

  let deleted = 0;
  const docs = [...found.appCases, ...found.appShots, ...found.who, ...found.supportShots, ...found.oldSupportTickets];
  for (let i = 0; i < docs.length; i += 400) {
    const writes = docs.slice(i, i + 400).map(d => ({delete: d.name}));
    await api.post(`/v1/projects/${project}/databases/(default)/documents:batchWrite`, {writes});
    deleted += writes.length;
  }
  for (const r of reports) {
    await api.patch(`/v1/${r.name}`, {fields: {screenshotPath: {stringValue: ''}}}, {queryParams: {'updateMask.fieldPaths': ['screenshotPath']}});
  }
  if (files.length) execSync(`gcloud storage rm "gs://${mumbai}/problemReports/**" --project=${project}`, {stdio: 'inherit'});
  console.log(`\nDeleted ${deleted} records and ${files.length} screenshot files; cleared ${reports.length} report screenshot links.`);
})().catch(e => { console.error(e.message); process.exitCode = 1; });
