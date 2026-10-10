const {test} = require('node:test');
const assert = require('node:assert/strict');

test('AI Agent Play Console integration: withEdit always cleans up, detects the policy gate', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  require('./index');
  const {GoogleAuth} = require('google-auth-library');
  const playConsole = require('./ai-agent-playconsole');

  // Stub GoogleAuth so no real ADC/network lookup happens — this must never
  // make a real call to androidpublisher.googleapis.com.
  const originalGetClient = GoogleAuth.prototype.getClient;
  GoogleAuth.prototype.getClient = async function () {
    return {getAccessToken: async () => ({token: 'fake-token'})};
  };
  const originalFetch = global.fetch;
  const calls = [];

  try {
    // Scenario 1: reading the production track hits Google's documented
    // post-2023 policy gate (personal accounts need a closed test first) —
    // the agent must report this as data, not throw a generic error, and
    // must still delete the edit it opened.
    global.fetch = async (url, init) => {
      const method = init?.method || 'GET';
      calls.push({url, method});
      if (method === 'POST' && url.endsWith('/edits')) return {ok: true, json: async () => ({id: 'edit1'})};
      if (method === 'GET' && url.includes('/edits/edit1/tracks/production')) {
        return {ok: false, status: 403, json: async () => ({error: {message: 'Changes to production track require a closed test with testers first.'}})};
      }
      if (method === 'DELETE' && url.endsWith('/edits/edit1')) return {ok: true, json: async () => ({})};
      throw new Error(`unexpected call: ${method} ${url}`);
    };
    const result = await playConsole.getTrackStatus({packageName: 'com.example.app', track: 'production'});
    assert.equal(result.policyGateBlocked, true);
    assert.match(result.reason, /testers/);
    assert.ok(calls.some(c => c.method === 'DELETE' && c.url.endsWith('/edits/edit1')), 'the edit must be deleted even when the policy gate is hit');

    // Scenario 2: a genuine, non-policy error inside the edit still must not
    // leave the edit dangling — withEdit's try/finally must delete it, then
    // rethrow the original error.
    calls.length = 0;
    global.fetch = async (url, init) => {
      const method = init?.method || 'GET';
      calls.push({url, method});
      if (method === 'POST' && url.endsWith('/edits')) return {ok: true, json: async () => ({id: 'edit2'})};
      if (method === 'DELETE' && url.endsWith('/edits/edit2')) return {ok: true, json: async () => ({})};
      return {ok: false, status: 500, json: async () => ({error: {message: 'boom'}})};
    };
    await assert.rejects(() => playConsole.getTrackStatus({packageName: 'com.example.app', track: 'beta'}), /boom/);
    assert.ok(calls.some(c => c.method === 'DELETE' && c.url.endsWith('/edits/edit2')), 'the edit must still be deleted after a non-policy error');
  } finally {
    global.fetch = originalFetch;
    GoogleAuth.prototype.getClient = originalGetClient;
  }
});
