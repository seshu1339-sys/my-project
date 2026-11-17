'use strict';
// Public links to photos in this project's Storage. In production that is https://firebasestorage.googleapis.com/...; inside the local
// Firebase emulators (FUNCTIONS_EMULATOR=true, used only for testing) photos live in the Storage emulator, so the same link points at it
// instead and the test apps can show them. Nothing changes in production.
const emulatorStorageHost = () =>
  process.env.FUNCTIONS_EMULATOR === 'true' && process.env.FIREBASE_STORAGE_EMULATOR_HOST ? process.env.FIREBASE_STORAGE_EMULATOR_HOST : '';

/// The public (download) link of [path] in [bucketName]; [extra] is added after ?alt=media (e.g. '&v=123').
function publicStorageUrl(bucketName, path, extra = '') {
  const host = emulatorStorageHost();
  return `${host ? `http://${host}` : 'https://firebasestorage.googleapis.com'}/v0/b/${bucketName}/o/${encodeURIComponent(path)}?alt=media${extra}`;
}

/// True for a link into Storage: Google's address always, the Storage emulator's only while testing in the emulators.
function isStorageUrl(url) {
  const v = String(url || '');
  if (/^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/[^/]+\/o\//.test(v)) return true;
  return process.env.FUNCTIONS_EMULATOR === 'true' && /^http:\/\/(127\.0\.0\.1|localhost|10\.0\.2\.2):9199\/v0\/b\/[^/]+\/o\//.test(v);
}

module.exports = {publicStorageUrl, isStorageUrl, emulatorStorageHost};
