'use strict';
// Face ID via browser WebAuthn/passkeys (the admin panel is used as a web app
// in Safari on the registered iPhone, not a native install). Registration
// happens once; Safari then prompts Face ID because authenticatorAttachment
// is 'platform' and no external authenticator is requested. The private key
// never leaves the iPhone's Secure Enclave — only the public key is ever
// stored here, and verification happens only here, server-side, never trusted
// from the client. One admin, one credential: this module does not support
// multiple registered devices per admin (matches "the registered trusted
// Admin iPhone", singular, from the spec).
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {generateRegistrationOptions, verifyRegistrationResponse, generateAuthenticationOptions, verifyAuthenticationResponse} = require('@simplewebauthn/server');
const {requireAdminSession} = require('./admin-session');
const {requireModuleEnabled} = require('./ai-agent-config');
const {writeAuditLog} = require('./ai-agent-audit-log');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};

// Must be the exact registrable domain (no scheme/port) the admin panel is
// actually opened from — the hidden admin route is reached at locamarket.in
// (the customer site's custom domain), not the e-commerce-app-a3897-admin.web.app
// default URL, so RP_ID has to match locamarket.in, not the Firebase-assigned
// hostname. 'locamarket.in' also covers www.locamarket.in (a WebAuthn RP ID
// may be any suffix of the actual origin's domain). Overridable via functions
// config/env for a different hosting domain without a code change.
const RP_ID = process.env.AI_AGENT_WEBAUTHN_RP_ID || 'locamarket.in';
const ORIGINS = (process.env.AI_AGENT_WEBAUTHN_ORIGINS || 'https://locamarket.in,https://www.locamarket.in').split(',');

function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
async function requireAdmin(request) {
  const uid = requireUser(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
  return uid;
}

exports.beginWebauthnRegistration = onCall(options, async request => {
  const uid = await requireAdmin(request);
  await requireModuleEnabled('faceId');
  const regOptions = await generateRegistrationOptions({
    rpName: 'Locamarket Admin',
    rpID: RP_ID,
    userID: Buffer.from(uid, 'utf8'),
    userName: request.auth.token.email || uid,
    attestationType: 'none',
    authenticatorSelection: {authenticatorAttachment: 'platform', userVerification: 'required', residentKey: 'preferred'},
  });
  await db.collection('_aiAgentWebauthnChallenges').doc(uid).set({challenge: regOptions.challenge, createdAt: FieldValue.serverTimestamp()});
  return regOptions;
});

exports.completeWebauthnRegistration = onCall(options, async request => {
  const uid = await requireAdmin(request);
  await requireModuleEnabled('faceId');
  const challengeSnap = await db.collection('_aiAgentWebauthnChallenges').doc(uid).get();
  if (!challengeSnap.exists) throw new HttpsError('failed-precondition', 'Start Face ID registration first.');
  let verification;
  try {
    verification = await verifyRegistrationResponse({
      response: request.data?.response,
      expectedChallenge: challengeSnap.data().challenge,
      expectedOrigin: ORIGINS,
      expectedRPID: RP_ID,
    });
  } catch (error) {
    throw new HttpsError('permission-denied', `Face ID registration could not be verified: ${error.message}`);
  }
  if (!verification.verified) throw new HttpsError('permission-denied', 'Face ID registration could not be verified.');
  const {credential} = verification.registrationInfo;
  await db.collection('_aiAgentWebauthnCredentials').doc(uid).set({
    credentialId: credential.id,
    publicKey: Buffer.from(credential.publicKey).toString('base64'),
    signCount: credential.counter,
    registeredAt: FieldValue.serverTimestamp(),
  });
  await challengeSnap.ref.delete();
  await writeAuditLog({uid, type: 'webauthn', action: 'register', detail: 'Face ID credential registered.'});
  return {ok: true};
});

exports.beginWebauthnAssertion = onCall(options, async request => {
  const uid = await requireAdmin(request);
  await requireModuleEnabled('faceId');
  const credSnap = await db.collection('_aiAgentWebauthnCredentials').doc(uid).get();
  if (!credSnap.exists) throw new HttpsError('failed-precondition', 'Register Face ID first, in AI Agent settings.');
  const authOptions = await generateAuthenticationOptions({
    rpID: RP_ID,
    userVerification: 'required',
    allowCredentials: [{id: credSnap.data().credentialId}],
  });
  await db.collection('_aiAgentWebauthnChallenges').doc(uid).set({challenge: authOptions.challenge, createdAt: FieldValue.serverTimestamp()});
  return authOptions;
});

exports.completeWebauthnAssertion = onCall(options, async request => {
  const uid = await requireAdmin(request);
  await requireModuleEnabled('faceId');
  const challengeSnap = await db.collection('_aiAgentWebauthnChallenges').doc(uid).get();
  const credSnap = await db.collection('_aiAgentWebauthnCredentials').doc(uid).get();
  if (!challengeSnap.exists || !credSnap.exists) throw new HttpsError('failed-precondition', 'Register Face ID first, in AI Agent settings.');
  const cred = credSnap.data();
  let verification;
  try {
    verification = await verifyAuthenticationResponse({
      response: request.data?.response,
      expectedChallenge: challengeSnap.data().challenge,
      expectedOrigin: ORIGINS,
      expectedRPID: RP_ID,
      credential: {id: cred.credentialId, publicKey: Buffer.from(cred.publicKey, 'base64'), counter: cred.signCount},
    });
  } catch (error) {
    throw new HttpsError('permission-denied', `Face ID could not be verified: ${error.message}`);
  }
  if (!verification.verified) throw new HttpsError('permission-denied', 'Face ID could not be verified.');
  await credSnap.ref.update({signCount: verification.authenticationInfo.newCounter});
  await challengeSnap.ref.delete();
  await writeAuditLog({uid, type: 'webauthn', action: 'assert', detail: 'Face ID verified.'});
  return {ok: true};
});
