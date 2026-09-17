// Uses the already signed-in Firebase CLI. Never logs or saves access tokens.
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const {checkBillingEnabled} = require(path.join(cli, 'gcp/cloudbilling'));
const {setAllowSmsRegionPolicy, findUser, setCustomClaim} = require(path.join(cli, 'gcp/auth'));
const {getIamPolicy, addServiceAccountToRoles} = require(path.join(cli, 'gcp/resourceManager'));
const project = 'e-commerce-app-a3897';
const mode = process.argv[2] || 'inspect';
(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const identity = new Client({urlPrefix: 'https://identitytoolkit.googleapis.com', auth: true});
  const storage = new Client({urlPrefix: 'https://firebasestorage.googleapis.com', auth: true});
  const configPath = `/admin/v2/projects/${project}/config`;
  if (mode === 'inspect-notifications') {
    const functions = new Client({urlPrefix: 'https://cloudfunctions.googleapis.com', auth: true});
    for (const name of ['notifyPriceDrop', 'notifyNewOffers']) {
      const result = (await functions.get(`/v2/projects/${project}/locations/asia-south1/functions/${name}`)).body;
      console.log(`${name}: ${result.state}`);
      if (result.state !== 'ACTIVE') throw Error(`${name} is not active`);
    }
    const scheduler = new Client({urlPrefix: 'https://cloudscheduler.googleapis.com', auth: true});
    const job = (await scheduler.get(`/v1/projects/${project}/locations/asia-south1/jobs/firebase-schedule-notifyNewOffers-asia-south1`)).body;
    console.log(`Offer schedule: ${job.state}, ${job.schedule}`);
    if (job.state !== 'ENABLED') throw Error('Offer schedule is not enabled');
    const services = new Client({urlPrefix: 'https://serviceusage.googleapis.com', auth: true});
    const messaging = (await services.get(`/v1/projects/${project}/services/fcm.googleapis.com`)).body;
    console.log(`FCM API: ${messaging.state}`);
    if (messaging.state !== 'ENABLED') throw Error('Enable the Firebase Cloud Messaging API before delivery');
    return;
  } else if (mode === 'configure-invokers') {
    const run = require(path.join(cli, 'gcp/run'));
    for (const name of ['pinlogin', 'setpin', 'placeorder']) {
      const resource = `projects/${project}/locations/us-central1/services/${name}`;
      const policy = await run.getIamPolicy(resource);
      policy.bindings ||= [];
      let binding = policy.bindings.find(b => b.role === 'roles/run.invoker' && !b.condition);
      if (!binding) { binding = {role: 'roles/run.invoker', members: []}; policy.bindings.push(binding); }
      if (!binding.members.includes('allUsers')) {
        binding.members.push('allUsers');
        await run.setIamPolicy(resource, policy);
      }
      const verified = await run.getIamPolicy(resource);
      if (!verified.bindings?.some(b => b.role === 'roles/run.invoker' && !b.condition && b.members?.includes('allUsers'))) throw Error(`Public invocation verification failed: ${name}`);
      console.log(`${name}: approved public invocation verified`);
    }
    return;
  } else if (mode === 'inspect-runtime' || mode === 'configure-runtime') {
    const functions = new Client({urlPrefix: 'https://cloudfunctions.googleapis.com', auth: true});
    const fn = (await functions.get(`/v2/projects/${project}/locations/us-central1/functions/pinLogin`)).body;
    const email = fn.serviceConfig?.serviceAccountEmail;
    if (!email) throw Error(`Runtime account is not available yet (function state: ${fn.state || 'unknown'}). Wait for deployment to complete.`);
    if (![`${project}@appspot.gserviceaccount.com`, '462582150390-compute@developer.gserviceaccount.com'].includes(email)) throw Error(`Unexpected runtime service account: ${email}. Inspect before changing permissions.`);
    const member = `serviceAccount:${email}`;
    let projectPolicy = await getIamPolicy(project);
    let roles = (projectPolicy.bindings || []).filter(b => !b.condition && b.members?.includes(member)).map(b => b.role);
    const iam = new Client({urlPrefix: 'https://iam.googleapis.com', auth: true});
    const resource = `/v1/projects/${project}/serviceAccounts/${email}`;
    let policy = (await iam.post(`${resource}:getIamPolicy`, {options: {requestedPolicyVersion: 3}})).body;
    const canSign = () => (policy.bindings || []).some(b => !b.condition && b.role === 'roles/iam.serviceAccountTokenCreator' && b.members?.includes(member));
    if (mode === 'configure-runtime') {
      const services = new Client({urlPrefix: 'https://serviceusage.googleapis.com', auth: true});
      const signingApi = `/v1/projects/${project}/services/iamcredentials.googleapis.com`;
      if ((await services.get(signingApi)).body.state !== 'ENABLED') await services.post(`${signingApi}:enable`, {});
      if (!roles.includes('roles/editor') && !roles.includes('roles/owner')) {
        const missing = ['roles/datastore.user', 'roles/firebaseauth.admin'].filter(role => !roles.includes(role));
        if (missing.length) await addServiceAccountToRoles(project, email, missing);
      }
      if (!canSign()) {
        policy.bindings ||= [];
        const binding = policy.bindings.find(b => b.role === 'roles/iam.serviceAccountTokenCreator' && !b.condition);
        if (binding) { binding.members ||= []; binding.members.push(member); }
        else policy.bindings.push({role: 'roles/iam.serviceAccountTokenCreator', members: [member]});
        await iam.post(`${resource}:setIamPolicy`, {policy});
      }
      projectPolicy = await getIamPolicy(project);
      roles = (projectPolicy.bindings || []).filter(b => !b.condition && b.members?.includes(member)).map(b => b.role);
      policy = (await iam.post(`${resource}:getIamPolicy`, {options: {requestedPolicyVersion: 3}})).body;
    }
    console.log(JSON.stringify({runtimeServiceAccount: email, projectRoles: roles, selfTokenSigningConfigured: canSign()}, null, 2));
    return;
  } else if (mode === 'lookup-email-owner' || mode === 'grant-email-owner') {
    const email = process.argv[3];
    if (!email || !email.includes('@')) throw Error('Provide the explicitly authorized owner email.');
    let owner;
    try { owner = await findUser(project, email, undefined, undefined); }
    catch (error) { if (error.message === 'No users found') { console.log(JSON.stringify({ownerAccountExists: false, nextStep: 'Register and verify your email first.'})); return; } throw error; }
    if (owner.disabled || !owner.emailVerified) throw Error('Owner must have an enabled, verified email account.');
    if (mode === 'grant-email-owner') await setCustomClaim(project, owner.uid, {admin: true}, {merge: true});
    const verified = await findUser(project, undefined, undefined, owner.uid);
    console.log(JSON.stringify({ownerAccountExists: true, emailVerified: verified.emailVerified, admin: JSON.parse(verified.customAttributes || '{}').admin === true}));
    return;
  } else if (mode === 'configure-email' || mode === 'configure-email-link') {
    await identity.patch(configPath + '?updateMask=signIn.email.enabled,signIn.email.passwordRequired,signIn.phoneNumber.enabled', {
      signIn: {email: {enabled: true, passwordRequired: mode !== 'configure-email-link'}, phoneNumber: {enabled: false}},
    });
  } else if (mode === 'configure-phone') {
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
      emailEnabled: auth.value.body.signIn?.email?.enabled === true,
      passwordRequired: auth.value.body.signIn?.email?.passwordRequired === true,
      authorizedDomains: auth.value.body.authorizedDomains,
      smsRegionConfig: auth.value.body.smsRegionConfig,
    } : {error: auth.reason.message},
    storage: bucket.status === 'fulfilled' ? bucket.value.body : {error: bucket.reason.message},
  };
  console.log(JSON.stringify(result, null, 2));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
