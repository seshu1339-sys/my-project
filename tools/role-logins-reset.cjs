// One-off clean-up for the switch to a separate login per role (functions/role-logins.js), run once at deploy time with the owner.
// Run from the repository root in a trusted shell with Application Default Credentials (gcloud auth application-default login):
//
//   node tools/role-logins-reset.cjs PROJECT_ID                       DRY RUN: lists everything and writes role-logins-reset-plan.json
//   node tools/role-logins-reset.cjs PROJECT_ID --apply PLAN.json     deletes exactly what that plan lists, nothing else
//
// What it lists (and --apply deletes):
//   - every emailRoles/<email> document (the old "one email = one role" lock; it held only test data);
//   - every Firebase Auth account EXCEPT the emails given with --keep (the admin's email must be kept: its password signs in to the
//     admin panel), together with the records stored under that account's uid in the role collections below.
// Nothing is deleted without --apply and a plan file the owner has looked at.
const path = require('node:path');
const fs = require('node:fs');
// Resolved from functions/ (its node_modules), so package subpaths like firebase-admin/app go through the package's exports map.
const req = require('node:module').createRequire(path.join(__dirname, '..', 'functions', 'package.json'));
const {initializeApp, applicationDefault} = req('firebase-admin/app');
const {getAuth} = req('firebase-admin/auth');
const {getFirestore} = req('firebase-admin/firestore');

const BY_UID = ['users', 'vendorApplications', 'vendors', 'providerApplications', 'providers', 'fieldStaff', 'quickAccounts', 'staffAreaStaff',
  'vendorPremium', 'vendorPlanStatus', 'vendorShowcase', 'vendorTodaysOffers', 'notificationSubscribers', 'userActivity', 'accountStates', 'consents'];

const args = process.argv.slice(2);
const projectId = args[0];
const applyIndex = args.indexOf('--apply');
const keep = new Set(args.flatMap((a, i) => (args[i - 1] === '--keep' ? [a.toLowerCase()] : [])));
if (!projectId || projectId.startsWith('--')) throw Error('Usage: node tools/role-logins-reset.cjs PROJECT_ID [--keep ADMIN_EMAIL ...] [--apply PLAN.json]');
initializeApp({credential: applicationDefault(), projectId});
const db = getFirestore();

async function dryRun() {
  const emailRoles = (await db.collection('emailRoles').get()).docs.map(d => ({id: d.id, role: d.data().role || ''}));
  const accounts = [];
  let pageToken;
  do {
    const page = await getAuth().listUsers(1000, pageToken);
    for (const user of page.users) {
      const email = String(user.email || user.customClaims?.loginEmail || '').toLowerCase();
      if (keep.has(email) && !user.customClaims?.role) continue;
      const records = [];
      for (const name of BY_UID) if ((await db.collection(name).doc(user.uid).get()).exists) records.push(`${name}/${user.uid}`);
      accounts.push({uid: user.uid, email, role: user.customClaims?.role || '(email login)', admin: user.customClaims?.admin === true,
        created: user.metadata.creationTime, lastSignIn: user.metadata.lastSignInTime || '', records});
    }
    pageToken = page.pageToken;
  } while (pageToken);
  const plan = {projectId, made: new Date().toISOString(), kept: [...keep], emailRoles, accounts};
  const file = path.resolve('role-logins-reset-plan.json');
  fs.writeFileSync(file, JSON.stringify(plan, null, 2));
  console.log(`emailRoles documents: ${emailRoles.length}`);
  for (const r of emailRoles) console.log(`  emailRoles/${r.id}  (${r.role})`);
  console.log(`\nFirebase Auth accounts to delete: ${accounts.length}  (kept: ${[...keep].join(', ') || 'none'})`);
  for (const a of accounts) console.log(`  ${a.email || '(no email)'}  ${a.role}${a.admin ? ' ADMIN' : ''}  uid=${a.uid}  last sign-in ${a.lastSignIn || 'never'}\n      records: ${a.records.join(', ') || 'none'}`);
  console.log(`\nDRY RUN ONLY. Nothing was deleted. The plan is in ${file}.`);
}

async function apply(planFile) {
  const plan = JSON.parse(fs.readFileSync(planFile, 'utf8'));
  if (plan.projectId !== projectId) throw Error(`The plan is for ${plan.projectId}, not ${projectId}.`);
  for (const r of plan.emailRoles) await db.collection('emailRoles').doc(r.id).delete();
  for (const a of plan.accounts) {
    // With its sub-collections (users/<uid>/pushTokens, consents/<uid>/log).
    for (const record of a.records) await db.recursiveDelete(db.doc(record));
    try { await getAuth().deleteUser(a.uid); } catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
    console.log(`deleted ${a.email || a.uid} (${a.role}) and ${a.records.length} record(s)`);
  }
  console.log(`Done: ${plan.emailRoles.length} emailRoles documents and ${plan.accounts.length} accounts.`);
}

(applyIndex >= 0 ? apply(args[applyIndex + 1]) : dryRun()).catch(e => { console.error(e.message); process.exitCode = 1; });
