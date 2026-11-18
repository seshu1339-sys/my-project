'use strict';
// Problem screenshots (owner, 18 Nov 2026: cost cuts part 3): every screenshot of a problem lives in ONE US bucket (us-central1, inside
// the Cloud Storage free 5 GB; the Mumbai bucket has no free tier), never in Firestore:
//   problems/<problemId>/<n>.jpg    the automatic screenshots of one problem (functions/modules/app-problems), at most 3 a problem
//   reports/<reportId>.<jpg|png>    the "Report a problem" screenshot
//   support/<ticketId>.<jpg|png>    the AI Support box screenshot (at most 3 for one problem)
// Each is small (the phone makes it about 30-60 KB; MAX_BYTES here). Deleted when the problem is solved (deleteShots) and by the
// bucket's own lifecycle rule after 30 days (set when the bucket is made: scripts/problem-shots-bucket.cjs). Only the admin sees
// them, through problemShot (no public link).
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getStorage} = require('firebase-admin/storage');
const {isAdminToken} = require('./role-auth');
const {requireAdminSession} = require('./admin-session');

const DEFAULT_BUCKET = 'e-commerce-app-a3897-problem-shots';
const MAX_PER_PROBLEM = 3;
const MAX_BYTES = 80 * 1024;
const PREFIXES = ['problems/', 'reports/', 'support/'];

/// The bucket's name (PROBLEM_SHOTS_BUCKET only for the tests and the emulator).
const bucketName = () => process.env.PROBLEM_SHOTS_BUCKET || DEFAULT_BUCKET;
const shotBucket = () => getStorage().bucket(bucketName());

/// A screenshot from an app (base64) as bytes and type, or null when there is none or it is not a small JPEG / PNG.
function shotBytes(base64, {maxBytes = MAX_BYTES} = {}) {
  if (typeof base64 !== 'string' || !base64 || base64.length > Math.ceil(maxBytes * 4 / 3) + 8) return null;
  const bytes = Buffer.from(base64, 'base64');
  if (!bytes.length || bytes.length > maxBytes) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return {bytes, type: 'image/jpeg', ext: 'jpg'};
  if (bytes[0] === 0x89 && bytes[1] === 0x50) return {bytes, type: 'image/png', ext: 'png'};
  return null;
}

/// Saves one screenshot at [path] (private: no download token, no public read).
async function saveShot(bucket, path, shot) {
  await bucket.file(path).save(shot.bytes, {contentType: shot.type, resumable: false, metadata: {cacheControl: 'private, max-age=0'}});
  return path;
}

/// Deletes every screenshot under [prefix] (a solved problem's folder, or one report / ticket file). Never throws.
async function deleteShots(bucket, prefix) {
  if (!PREFIXES.some(p => prefix.startsWith(p) && prefix.length > p.length)) return;
  try {
    await bucket.deleteFiles({prefix, force: true});
  } catch (error) {
    console.warn('Screenshots not deleted', prefix, error.message);
  }
}

/// The folder of one problem's automatic screenshots.
const problemFolder = problemId => `problems/${String(problemId).replace(/[^a-zA-Z0-9~_-]/g, '_')}/`;

/// A path an admin may open: inside one of the three folders, no climbing out.
const validPath = path => typeof path === 'string' && path.length < 300 && PREFIXES.some(p => path.startsWith(p)) && !path.includes('..');

/// Admin only: one screenshot as base64 (they are small), or {data: ''} when it was deleted (solved or older than 30 days).
async function readShot(bucket, path) {
  if (!validPath(path)) throw new HttpsError('invalid-argument', 'That screenshot was not found.');
  const file = bucket.file(path);
  const [exists] = await file.exists();
  if (!exists) return {data: '', type: ''};
  const [bytes] = await file.download();
  const [meta] = await file.getMetadata();
  return {data: bytes.toString('base64'), type: meta.contentType || 'image/jpeg'};
}

exports.problemShot = onCall({region: 'us-central1', maxInstances: 2, memory: '256MiB'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
  return readShot(shotBucket(), request.data?.path);
});

exports.shots = {bucketName, shotBucket, shotBytes, saveShot, deleteShots, problemFolder, validPath, readShot, MAX_PER_PROBLEM, MAX_BYTES, DEFAULT_BUCKET};
