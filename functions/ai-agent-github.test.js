const {test} = require('node:test');
const assert = require('node:assert/strict');

test('AI Agent GitHub integration: JWT shape/signature, not-configured refusal, token caching', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  require('./index');
  const {getFirestore} = require('firebase-admin/firestore');
  const {generateKeyPairSync, createVerify} = require('node:crypto');
  const db = getFirestore();
  const github = require('./ai-agent-github');

  // signAppJwt produces a well-formed, correctly RS256-signed JWT — verified
  // with a throwaway keypair, never a real GitHub App key.
  const {privateKey: pem, publicKey} = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    privateKeyEncoding: {type: 'pkcs1', format: 'pem'},
    publicKeyEncoding: {type: 'spki', format: 'pem'},
  });
  const jwt = github.signAppJwt('app-12345', pem);
  const [headerB64, payloadB64, sigB64] = jwt.split('.');
  const header = JSON.parse(Buffer.from(headerB64, 'base64url').toString());
  const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString());
  assert.deepEqual(header, {alg: 'RS256', typ: 'JWT'});
  assert.equal(payload.iss, 'app-12345');
  assert.ok(payload.exp > payload.iat);
  const verifier = createVerify('RSA-SHA256');
  verifier.update(`${headerB64}.${payloadB64}`);
  verifier.end();
  const signature = Buffer.from(sigB64.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  assert.ok(verifier.verify(publicKey, signature), 'JWT signature must verify against the signing key');

  // Not configured yet -> a clear refusal, never a real network call.
  await db.collection('aiAgentConfig').doc('global').set({integrations: {}}, {merge: true});
  await assert.rejects(() => github.getInstallationToken(), /not configured yet/);

  // Token caching: once minted with a future expiry, a second call is served
  // from the in-memory cache without a second network call. No real secret
  // is bound outside a deployed function, so the private-key getter is
  // stubbed to a throwaway value for this part only.
  const originalFetch = global.fetch;
  const originalValue = github.privateKey.value;
  let fetchCalls = 0;
  global.fetch = async () => {
    fetchCalls++;
    return {ok: true, json: async () => ({token: 'cached-token-abc', expires_at: new Date(Date.now() + 3600 * 1000).toISOString()})};
  };
  github.privateKey.value = () => pem; // the throwaway keypair generated above — never a real App key
  try {
    await db.collection('aiAgentConfig').doc('global').set({integrations: {github: {appId: 'app1', installationId: 'inst1'}}}, {merge: true});
    const token1 = await github.getInstallationToken();
    const token2 = await github.getInstallationToken();
    assert.equal(token1, 'cached-token-abc');
    assert.equal(token2, 'cached-token-abc');
    assert.equal(fetchCalls, 1, 'the second call must be served from cache, not a second network call');
  } finally {
    global.fetch = originalFetch;
    github.privateKey.value = originalValue;
  }
});
