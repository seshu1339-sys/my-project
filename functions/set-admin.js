// Run only in a trusted environment with Application Default Credentials.
// Usage: node functions/set-admin.js PROJECT_ID EXISTING_USER_UID
const {initializeApp, applicationDefault} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const [projectId, uid] = process.argv.slice(2);
if (!projectId || !uid) throw Error('Usage: node functions/set-admin.js PROJECT_ID EXISTING_USER_UID');
initializeApp({credential: applicationDefault(), projectId});
(async () => {
  const user = await getAuth().getUser(uid);
  if (!user.email || !user.emailVerified || user.disabled) throw Error('Owner must have an enabled, verified email account.');
  await getAuth().setCustomUserClaims(uid, {...user.customClaims, admin: true});
  console.log('Administrator access granted. Sign out and sign back in to refresh claims.');
})().catch(e => { console.error(e.message); process.exitCode = 1; });
