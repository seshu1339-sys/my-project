'use strict';
// Minimal, additive role layer on top of the single admin:true claim. A
// plain helper (not a callable) — every agent callable that needs it calls
// requireRole(uid, minRole) once, right after its existing
// requireModuleEnabled(action.module) check. aiAgentRoles/{uid} is written
// only by scripts/firebase-setup.cjs's `grant-agent-role` mode (a one-time,
// human-run bootstrap step), never by any callable.
const {HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const db = getFirestore();

const ROLE_RANK = {viewer: 0, operator: 1, owner: 2};

// While aiAgentRoles is completely empty, every admin is treated as 'owner'
// so the existing admin account isn't locked out the moment this ships.
// Writing the first real role doc (via `grant-agent-role`) ends this
// carve-out for everyone else from then on.
async function getRole(uid) {
  const snap = await db.collection('aiAgentRoles').doc(uid).get();
  if (snap.exists) return snap.data().role;
  const any = await db.collection('aiAgentRoles').limit(1).get();
  return any.empty ? 'owner' : 'viewer';
}

async function requireRole(uid, minRole) {
  const role = await getRole(uid);
  if ((ROLE_RANK[role] ?? -1) < (ROLE_RANK[minRole] ?? 99)) {
    throw new HttpsError('permission-denied', `This action requires the "${minRole}" role; you have "${role}".`);
  }
}

module.exports = {requireRole, getRole, ROLE_RANK};
