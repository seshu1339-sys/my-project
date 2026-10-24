// Builds a signed release AAB for one flavor and uploads it to a Google Play track.
//
//   node tools/play-upload/upload.mjs <customer|vendor|staff> [--track internal] [--check] [--no-build] [--yes]
//
//   --check     only test the key and the app's permissions (nothing is built or uploaded)
//   --no-build  upload the AAB that is already built (the version code is not changed)
//   --yes       really upload; without it the script stops after the build and says what it would do
//
// The service-account key stays where it is (never printed, copied or committed): its path comes from
// PLAY_KEY_FILE, else the default below. The production track is refused on purpose.
import { execFileSync } from 'node:child_process';
import { createReadStream, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { GoogleAuth } from 'google-auth-library';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const KEY_FILE = process.env.PLAY_KEY_FILE ?? 'C:/Users/Lappy/Downloads/e-commerce-app-a3897-929f4780e4f2.json';

const FLAVORS = {
  customer: { packageName: 'in.locamarket.locamark', main: 'lib/main.dart', config: 'firebase-config-android.json' },
  vendor: { packageName: 'in.locamarket.vendor', main: 'lib/main_vendor.dart', config: 'firebase-config-android-vendor.json' },
  staff: { packageName: 'in.locamarket.staff', main: 'lib/main_field.dart', config: 'firebase-config-android-staff.json' },
};

const args = process.argv.slice(2);
const flavor = args.find((a) => !a.startsWith('--'));
const flag = (name) => args.includes(`--${name}`);
const track = args.includes('--track') ? args[args.indexOf('--track') + 1] : 'internal';
const app = FLAVORS[flavor];
if (!app) fail(`Say which app: ${Object.keys(FLAVORS).join(' | ')}`);
if (track === 'production') fail('The production track is blocked in this script on purpose. Release to production by hand in Play Console.');

function fail(message) {
  console.error(message);
  process.exit(1);
}

const auth = new GoogleAuth({ keyFile: KEY_FILE, scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
const api = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${app.packageName}`;
async function call(method, path, extra = {}) {
  const client = await auth.getClient();
  return (await client.request({ url: api + path, method, ...extra })).data;
}

/** Highest version code Play already has for this app, on any track (0 when nothing was uploaded yet). */
async function highestPlayVersionCode(editId) {
  const { tracks = [] } = await call('GET', `/edits/${editId}/tracks`);
  const codes = tracks.flatMap((t) => (t.releases ?? []).flatMap((r) => (r.versionCodes ?? []).map(Number)));
  return codes.length ? Math.max(...codes) : 0;
}

const pubspecPath = join(root, 'pubspec.yaml');
const versionLine = /^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m;

async function main() {
  console.log(`App: ${flavor} (${app.packageName}), track: ${track}`);
  const edit = await call('POST', '/edits', { data: {} });
  let playMax;
  try {
    playMax = await highestPlayVersionCode(edit.id);
  } finally {
    await call('DELETE', `/edits/${edit.id}`).catch(() => {});
  }
  const pubspec = readFileSync(pubspecPath, 'utf8');
  const [, name, build] = pubspec.match(versionLine) ?? fail('Could not find "version: x.y.z+n" in pubspec.yaml');
  console.log(`Key and permissions OK. Highest version code on Play: ${playMax || 'none yet'}; pubspec now: ${name}+${build}`);
  if (flag('check')) return;

  let code = Number(build);
  if (!flag('no-build')) {
    code = Math.max(Number(build), playMax) + 1;
    if (code !== Number(build)) {
      writeFileSync(pubspecPath, pubspec.replace(versionLine, `version: ${name}+${code}`));
      console.log(`pubspec.yaml version changed to ${name}+${code}`);
    }
    console.log('Building the signed release bundle (a few minutes)...');
    execFileSync('flutter', ['build', 'appbundle', '--release', '--flavor', flavor, '-t', app.main, `--dart-define-from-file=${app.config}`],
      { cwd: root, stdio: 'inherit', shell: true });
  } else if (code <= playMax) {
    fail(`pubspec version code ${code} is not above Play's ${playMax}; build again without --no-build.`);
  }

  const aab = join(root, 'build', 'app', 'outputs', 'bundle', `${flavor}Release`, `app-${flavor}-release.aab`);
  const sizeMb = (statSync(aab).size / 1048576).toFixed(1);
  console.log(`Bundle: ${aab} (${sizeMb} MB), version ${name}+${code}`);
  if (!flag('yes')) {
    console.log(`Stopped before uploading. Add --yes to upload it to the "${track}" track.`);
    return;
  }

  const upload = await call('POST', '/edits', { data: {} });
  const bundle = await (await auth.getClient()).request({
    url: `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${app.packageName}/edits/${upload.id}/bundles?uploadType=media`,
    method: 'POST',
    headers: { 'Content-Type': 'application/octet-stream' },
    data: createReadStream(aab),
    maxContentLength: Infinity,
    maxBodyLength: Infinity,
    timeout: 20 * 60 * 1000,
  });
  const versionCode = bundle.data.versionCode;
  console.log(`Uploaded, Play version code ${versionCode}`);
  await call('PUT', `/edits/${upload.id}/tracks/${track}`, {
    data: { track, releases: [{ name: `${name} (${versionCode})`, status: 'completed', versionCodes: [String(versionCode)] }] },
  });
  await call('POST', `/edits/${upload.id}:commit`);
  console.log(`Done: ${flavor} ${name}+${versionCode} is on the "${track}" track.`);
}

main().catch((error) => {
  const detail = error?.response?.data?.error?.message ?? error.message;
  fail(`Failed: ${detail}`);
});
