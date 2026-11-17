// Run only in a trusted environment with Application Default Credentials.
// Usage: node functions/set-admin.js PROJECT_ID ADMIN_EMAIL
//
// Makes ADMIN_EMAIL's administrator login (functions/role-logins.js): a separate login, with its own ID and the claims
// {role: 'admin', loginEmail, admin: true}. The admin panel signs in with the email's password and then enters this login, so admin
// power never reaches the same email's customer, vendor, provider or staff login. Any old admin claim on the email's own login is
// removed. The email's own login must already exist, be verified and enabled (it is the password sign-in of the admin panel).
const {initializeApp, applicationDefault} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const [projectId, rawEmail] = process.argv.slice(2);
if (!projectId || !rawEmail || !rawEmail.includes('@')) throw Error('Usage: node functions/set-admin.js PROJECT_ID ADMIN_EMAIL');
initializeApp({credential: applicationDefault(), projectId});
const {roleLoginFor} = require('./role-logins');
(async () => {
  const email = rawEmail.trim().toLowerCase();
  const own = await getAuth().getUserByEmail(email);
  if (!own.emailVerified || own.disabled) throw Error('The admin email must have an enabled, verified account (with a password for the admin panel).');
  const uid = await roleLoginFor('admin', email);
  if (own.customClaims?.admin) {
    const {admin, ...rest} = own.customClaims;
    await getAuth().setCustomUserClaims(own.uid, rest);
    console.log('Removed the old admin claim from the email\'s own login.');
  }
  console.log(`Administrator login ready: ${uid}. Sign in to the admin panel with ${email} and its password.`);
})().catch(e => { console.error(e.message); process.exitCode = 1; });
