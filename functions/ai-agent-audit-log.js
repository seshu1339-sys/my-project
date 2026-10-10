'use strict';
// Shared, append-only audit trail for every AI Admin Agent module. A plain
// helper (not a callable) — every other ai-agent-*.js file calls writeAuditLog
// directly; nothing ever edits or deletes an entry once written. The admin UI
// reads this collection live via firestore.rules (admin-read-only).
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const db = getFirestore();

async function writeAuditLog({uid, type, action, detail, result}) {
  await db.collection('aiAgentAuditLog').add({
    uid: uid || null,
    type,
    action: action || null,
    detail: detail || null,
    result: result || null,
    at: FieldValue.serverTimestamp(),
  });
}

module.exports = {writeAuditLog};
