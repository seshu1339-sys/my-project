'use strict';
// The permanent block list (owner, 13 Nov 2026). Only the admin blocks someone for good, after looking at the reports
// (functions/modules/abuse-reports). A blocked email or phone number cannot register again in any app or sign in to any role:
//   blockedContacts/<key>   {key, kind: 'email' | 'phone', value, reason, blockedBy, blockedAt}   admin only
// key is "email:<lowercase email>" or "phone:<last 10 digits>". Checked by enterRole (every app's sign-in), registerVendor,
// registerProvider and requestFieldStaffAccess.
const {HttpsError} = require('firebase-functions/v2/https');

const BLOCKED_MESSAGE = 'This email or phone number is blocked by LOCAMARKET. If you think this is a mistake, write to the Support Team.';

const normEmail = value => String(value ?? '').trim().toLowerCase();
const normPhone = value => {
  const digits = String(value ?? '').replace(/\D/g, '');
  return digits.length >= 10 ? digits.slice(-10) : '';
};

/// The block-list keys of some emails and phone numbers (blank and odd values are left out).
function contactKeys({emails = [], phones = []} = {}) {
  const keys = new Set();
  for (const email of emails) if (normEmail(email).includes('@')) keys.add(`email:${normEmail(email)}`);
  for (const phone of phones) if (normPhone(phone)) keys.add(`phone:${normPhone(phone)}`);
  return [...keys];
}

/// The first blocked key among the contacts, or null.
async function blockedKey(db, contacts) {
  for (const key of contactKeys(contacts)) {
    if ((await db.collection('blockedContacts').doc(key).get()).exists) return key;
  }
  return null;
}

/// Throws "blocked" when any of the contacts is on the list.
async function assertNotBlocked(db, contacts) {
  if (await blockedKey(db, contacts)) throw new HttpsError('permission-denied', BLOCKED_MESSAGE);
}

/// Adds the contacts to the list (admin). Returns the keys written.
async function blockContacts(db, contacts, {reason = '', by = ''} = {}) {
  const keys = contactKeys(contacts);
  const batch = db.batch();
  for (const key of keys) {
    const [kind, value] = key.split(/:(.*)/s);
    batch.set(db.collection('blockedContacts').doc(key), {key, kind, value, reason: String(reason).slice(0, 300), blockedBy: by, blockedAt: new Date()}, {merge: true});
  }
  if (keys.length) await batch.commit();
  return keys;
}

module.exports = {BLOCKED_MESSAGE, normEmail, normPhone, contactKeys, blockedKey, assertNotBlocked, blockContacts};
