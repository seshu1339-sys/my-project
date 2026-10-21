// Checks that a RELEASE Android build of one flavor contains only its own screens (the compiler leaves out code
// nothing in that app can reach). Usage, after building the three release APKs:
//   node scripts/check-app-isolation.cjs
// It unzips lib/arm64-v8a/libapp.so from build/app/outputs/flutter-apk/app-<flavor>-release.apk and looks for text that
// only another app's screens contain.
const zlib = require('node:zlib');
const fs = require('node:fs');
const path = require('node:path');

const apkDir = path.join(__dirname, '..', 'build', 'app', 'outputs', 'flutter-apk');
// text that must be present / must be absent in each app's compiled code
const rules = {
  customer: { has: ['Choose your location', "Today's"], hasNot: ['jyothi9', 'Business Studio', 'Vendor studio', 'Field Assistant', 'Staff sign-in', 'approveVendor', 'reviewQuickItems', 'createQuickAccount'] },
  vendor: { has: ['Vendor studio'], hasNot: ['jyothi9', 'Business Studio', 'Field Assistant', 'Staff sign-in', 'approveVendor', 'reviewQuickItems', 'createQuickAccount', "Today's Best Offers"] },
  staff: { has: ['Field Assistant', 'Staff sign-in'], hasNot: ['jyothi9', 'Business Studio', 'Vendor studio', 'approveVendor', 'reviewQuickItems', 'createQuickAccount', "Today's Best Offers"] },
};
// A minimal zip reader (an APK is a zip): finds one entry by name and inflates it.
function readZipEntry(file, name) {
  const buf = fs.readFileSync(file);
  let end = buf.length - 22;
  while (end >= 0 && buf.readUInt32LE(end) !== 0x06054b50) end--;
  let pos = buf.readUInt32LE(end + 16);
  const count = buf.readUInt16LE(end + 10);
  for (let i = 0; i < count; i++) {
    const method = buf.readUInt16LE(pos + 10), size = buf.readUInt32LE(pos + 20);
    const nameLength = buf.readUInt16LE(pos + 28), extraLength = buf.readUInt16LE(pos + 30), commentLength = buf.readUInt16LE(pos + 32);
    const local = buf.readUInt32LE(pos + 42);
    if (buf.toString('utf8', pos + 46, pos + 46 + nameLength) === name) {
      const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
      const data = buf.subarray(start, start + size);
      return method === 0 ? data : zlib.inflateRawSync(data);
    }
    pos += 46 + nameLength + extraLength + commentLength;
  }
  throw new Error(name + ' not found in ' + file);
}
let failed = false;
for (const [flavor, rule] of Object.entries(rules)) {
  const apk = path.join(apkDir, `app-${flavor}-release.apk`);
  if (!fs.existsSync(apk)) { console.log(`SKIP ${flavor}: build it first (flutter build apk --release --flavor ${flavor} ...)`); continue; }
  const bytes = readZipEntry(apk, 'lib/arm64-v8a/libapp.so').toString('latin1');
  for (const text of rule.has) { const ok = bytes.includes(text); if (!ok) failed = true; console.log(`${ok ? 'PASS' : 'FAIL'} ${flavor} contains "${text}"`); }
  for (const text of rule.hasNot) { const ok = !bytes.includes(text); if (!ok) failed = true; console.log(`${ok ? 'PASS' : 'FAIL'} ${flavor} does not contain "${text}"`); }
}
process.exit(failed ? 1 : 0);
