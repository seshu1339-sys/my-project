// One-time fix, safe to re-run. Sets the admin-configurable theme colors
// (settings/theme — already the live site's actual color source; AppTokens
// in the Dart code is only ever the *fallback* when this doc is unset) to
// the premium green-primary palette. Reversible any time via Admin -> Theme
// Settings.
'use strict';
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';

async function setDoc(firestore, collection, id, data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) fields[k] = {stringValue: v};
  const fieldPaths = Object.keys(data).map(k => 'updateMask.fieldPaths=' + encodeURIComponent(k)).join('&');
  await firestore.patch(
    `/v1/projects/${project}/databases/(default)/documents/${collection}/${id}?${fieldPaths}`,
    {fields},
  );
}

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  await setDoc(firestore, 'settings', 'theme', {
    primary: '#16A34A',
    secondary: '#FF8A3D',
    background: '#FFF8F0',
    appBar: '#FFF3E0',
  });
  console.log('settings/theme updated: primary=#16A34A, secondary=#FF8A3D, background=#FFF8F0, appBar=#FFF3E0');
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
