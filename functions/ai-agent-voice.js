'use strict';
// Voice "speaker verification" — honestly, this is a passphrase-knowledge
// check (the browser transcribes speech to text; this compares the
// normalized transcript to a stored hash), not true biometric voiceprint
// matching. The `provider` field is the documented seam for a real
// voiceprint-matching API later: swap the body of verifyVoice's 'text-match'
// branch for a provider call, with zero change to anything that calls this
// module.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {createHash} = require('node:crypto');
const {requireAdminSession} = require('./admin-session');
const {requireModuleEnabled, getConfigData} = require('./ai-agent-config');
const {writeAuditLog} = require('./ai-agent-audit-log');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};

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

function normalize(text) {
  return String(text || '').toLowerCase().replace(/[^a-z0-9 ]/g, '').replace(/\s+/g, ' ').trim();
}
const sha256 = value => createHash('sha256').update(value).digest('hex');

exports.enrollAgentVoicePassphrase = onCall(options, async request => {
  const uid = await requireAdmin(request);
  await requireModuleEnabled('speakerVerification');
  const passphrase = normalize(request.data?.passphrase);
  if (passphrase.length < 8) throw new HttpsError('invalid-argument', 'Choose a passphrase of at least a few words.');
  await db.collection('_aiAgentVoiceEnrollment').doc(uid).set({
    provider: 'text-match',
    passphraseHash: sha256(passphrase),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await writeAuditLog({uid, type: 'voice', action: 'enroll', detail: 'Voice passphrase enrolled.'});
  return {ok: true};
});

exports.verifyAgentVoice = onCall(options, async request => {
  const uid = await requireAdmin(request);
  await requireModuleEnabled('speakerVerification');
  const transcript = normalize(request.data?.transcript);
  if (!transcript) throw new HttpsError('invalid-argument', 'No voice transcript received.');
  const snap = await db.collection('_aiAgentVoiceEnrollment').doc(uid).get();
  if (!snap.exists) throw new HttpsError('failed-precondition', 'Enroll a voice passphrase first, in AI Agent settings.');
  const enrollment = snap.data();
  // Only the zero-cost 'text-match' provider exists today; config.voiceProvider
  // is read here so a future real voiceprint provider can be dispatched to
  // without this callable's signature ever changing.
  const config = await getConfigData();
  const provider = enrollment.provider || config.voiceProvider || 'text-match';
  let verified = false;
  if (provider === 'text-match') {
    verified = sha256(transcript) === enrollment.passphraseHash;
  } else {
    throw new HttpsError('failed-precondition', `Voice provider "${provider}" is not yet implemented.`);
  }
  if (!verified) {
    await writeAuditLog({uid, type: 'voice', action: 'verify', result: 'denied'});
    throw new HttpsError('permission-denied', 'Voice passphrase did not match.');
  }
  await writeAuditLog({uid, type: 'voice', action: 'verify', result: 'granted'});
  return {ok: true};
});
