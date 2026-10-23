// Makes "Today's Offers" (settings/section_notice) independent of the Scrolling Text (settings/scrollingText): copies the values the banner was
// inheriting into its own record and sets independent=true, so the banner looks exactly as before but no longer changes when the Scrolling Text does.
// Without --apply it only shows what it would do. Run from the repo root: node scripts/decouple-notice.cjs [--apply]
'use strict';
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';
const KEYS = ['backgroundColor', 'backgroundImage', 'borderColor', 'borderWidth', 'brightness', 'gradientStart', 'gradientEnd', 'opacity', 'radius', 'textColor', 'fontFamily', 'fontStyle', 'fontWeight', 'fontSize', 'text', 'translations'];
(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const api = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});
  const base = `/v1/projects/${project}/databases/(default)/documents/settings`;
  const read = async id => { try { return (await api.get(`${base}/${id}`)).body.fields || {}; } catch (e) { if (e.status === 404) return null; throw e; } };
  const scrolling = await read('scrollingText'), notice = await read('section_notice');
  if (notice?.independent?.booleanValue === true) { console.log('Already independent. Nothing to do.'); return; }
  const copy = {};
  for (const key of KEYS) {
    const value = scrolling?.[key];
    const empty = !value || (value.stringValue !== undefined && value.stringValue === '');
    if (!empty && !(notice && key in notice)) copy[key] = value;
  }
  console.log('Values the banner inherits and will now own:', Object.keys(copy).join(', ') || '(none)');
  if (!process.argv.includes('--apply')) { console.log('Nothing written. Run again with --apply to do it.'); return; }
  const fields = {...copy, independent: {booleanValue: true}};
  if (!notice) fields.section = {stringValue: 'notice'};
  await api.patch(`${base}/section_notice`, {fields}, {queryParams: {'updateMask.fieldPaths': Object.keys(fields)}});
  const after = await read('section_notice');
  console.log('Done. independent =', after.independent?.booleanValue, '| fields now:', Object.keys(after).length);
})().catch(e => { console.error(e.message); process.exitCode = 1; });
