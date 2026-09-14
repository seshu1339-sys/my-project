// Uses the already signed-in Firebase CLI. Never logs or saves access tokens.
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const {checkBillingEnabled} = require(path.join(cli, 'gcp/cloudbilling'));
const {setAllowSmsRegionPolicy} = require(path.join(cli, 'gcp/auth'));
const project = 'e-commerce-app-a3897';
const mode = process.argv[2] || 'inspect';
(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const identity = new Client({urlPrefix: 'https://identitytoolkit.googleapis.com', auth: true});
  const storage = new Client({urlPrefix: 'https://firebasestorage.googleapis.com', auth: true});
  const configPath = `/admin/v2/projects/${project}/config`;
  if (mode === 'configure-phone') {
    const config = (await identity.get(configPath, {headers: {'x-goog-user-project': project}})).body;
    const regions = config.smsRegionConfig?.allowlistOnly?.allowedRegions || [];
    if (config.smsRegionConfig?.allowByDefault) throw Error('An existing broad SMS policy needs review before changing it.');
    await setAllowSmsRegionPolicy(project, [...new Set([...regions, 'IN'])]);
  } else if (mode === 'create-storage') {
    if (!await checkBillingEnabled(project)) throw Error('Blaze billing is not enabled. Complete the billing upgrade before creating Storage.');
    try {
      await storage.get(`/v1alpha/projects/${project}/defaultBucket`);
    } catch (error) {
      if (error.status !== 404) throw error;
      // Match the existing Firestore database region. This never changes billing.
      await storage.post(`/v1alpha/projects/${project}/defaultBucket`, {location: 'asia-south1'});
    }
  } else if (mode !== 'inspect') throw Error('Unsupported setup action');
  const results = await Promise.allSettled([
    checkBillingEnabled(project),
    identity.get(configPath, {headers: {'x-goog-user-project': project}}),
    storage.get(`/v1alpha/projects/${project}/defaultBucket`),
  ]);
  const [billing, auth, bucket] = results;
  const result = {
    project,
    billingEnabled: billing.status === 'fulfilled' ? billing.value : 'check-failed',
    authentication: auth.status === 'fulfilled' ? {
      phoneEnabled: auth.value.body.signIn?.phoneNumber?.enabled === true,
      authorizedDomains: auth.value.body.authorizedDomains,
      smsRegionConfig: auth.value.body.smsRegionConfig,
    } : {error: auth.reason.message},
    storage: bucket.status === 'fulfilled' ? bucket.value.body : {error: bucket.reason.message},
  };
  console.log(JSON.stringify(result, null, 2));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
