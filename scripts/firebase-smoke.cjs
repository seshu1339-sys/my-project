// Read-only deployment checks: invalid/unauthenticated requests never create data.
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {createHash} = require('node:crypto');
const path = require('node:path');
const project = 'e-commerce-app-a3897';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
(async () => {
  const site = `https://${project}.web.app`;
  const html = await fetch(site, {signal: AbortSignal.timeout(30000)});
  assert.equal(html.status, 200);
  assert.match(await html.text(), /Neighbourly/);
  const bundle = await fetch(`${site}/main.dart.js`, {signal: AbortSignal.timeout(30000)});
  assert.equal(bundle.status, 200);
  const local = readFileSync(path.join(__dirname, '../build/web/main.dart.js'));
  assert.equal(digest(Buffer.from(await bundle.arrayBuffer())), digest(local), 'Hosted bundle differs from local release');
  assert(local.includes(Buffer.from(project)), 'Build is missing the live Firebase project');
  console.log('PASS: HTTPS website serves the exact Firebase-connected release.');
  if (process.argv.includes('--hosting-only')) return;
  for (const [name, expectedStatus, expectedCode] of [['pinLogin', 400, 'INVALID_ARGUMENT'], ['setPin', 401, 'UNAUTHENTICATED'], ['placeOrder', 401, 'UNAUTHENTICATED']]) {
    const result = await fetch(`https://us-central1-${project}.cloudfunctions.net/${name}`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({data: {}}), signal: AbortSignal.timeout(60000)});
    const raw = await result.text();
    assert.match(result.headers.get('content-type') || '', /application\/json/, `${name}: HTTP ${result.status}, ${raw.slice(0, 180)}`);
    const body = JSON.parse(raw);
    assert.equal(result.status, expectedStatus, `${name}: unexpected HTTP status`);
    assert.equal(body.error?.status, expectedCode, `${name}: incorrect authentication/validation response`);
    console.log(`PASS: ${name} rejects invalid or unauthenticated requests.`);
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
