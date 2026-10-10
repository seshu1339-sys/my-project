// One-time fix, safe to re-run. Makes the homepage noticeably more compact
// at normal (100%) browser zoom — matching what the user sees today only by
// zooming their browser out to ~50% — using the app's EXISTING
// admin-configurable "scale" + global font-size + page padding/gap settings
// (ComponentLayout.scale reads `desktopScale` per section; see
// lib/ui/layout_settings.dart). No code change, no redeploy needed: this is
// pure Firestore settings data, reversible any time via the admin panel
// (Section Customization / Theme Settings).
'use strict';
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';

function encodeValue(v) {
  if (typeof v === 'string') return {stringValue: v};
  if (typeof v === 'number') return Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v};
  return {stringValue: String(v)};
}
async function setDoc(firestore, collection, id, data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) fields[k] = encodeValue(v);
  const fieldPaths = Object.keys(data).map(k => 'updateMask.fieldPaths=' + encodeURIComponent(k)).join('&');
  await firestore.patch(
    `/v1/projects/${project}/databases/(default)/documents/${collection}/${id}?${fieldPaths}`,
    {fields},
  );
}

// Every section that supports the desktopScale lever, shrunk to ~70% —
// scales heights/images/icon sizes proportionally wherever each widget
// already multiplies by ComponentLayout.scale.
const sections = [
  'header', 'logo', 'notice', 'promo', 'categories', 'popular',
  'localServices', 'ads', 'boxes', 'nearby', 'background', 'search', 'products',
];

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  for (const key of sections) {
    await setDoc(firestore, 'settings', `section_${key}`, {desktopScale: 0.72});
    console.log(`section_${key}: desktopScale=0.72`);
  }
  // Global text size (main.dart: fontSizeFactor = fontSize/14) and the
  // overall page gutter/section-gap, both already admin-configurable.
  await setDoc(firestore, 'settings', 'theme', {fontSize: 12});
  console.log('theme: fontSize=12');
  await setDoc(firestore, 'settings', 'section_background', {padding: 14, gap: 10});
  console.log('section_background: padding=14, gap=10');
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
