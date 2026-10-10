'use strict';
// Read-only health monitoring for the AI Admin Agent itself: counts recent
// denied/failed actions in the audit log and checks backup freshness, then
// emails an alert if something looks wrong. This module NEVER writes
// business data — the only writes it ever makes are its own audit-log entry
// and (via its own small mail snippet, not shared with admin-otp.js, per this
// codebase's existing "duplicate small helpers" convention) sending mail.
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {defineSecret} = require('firebase-functions/params');
const {getFirestore} = require('firebase-admin/firestore');
const {getConfigData} = require('./ai-agent-config');
const {writeAuditLog} = require('./ai-agent-audit-log');
const db = getFirestore();

const mailUser = defineSecret('ADMIN_MAIL_USER');
const mailPassword = defineSecret('ADMIN_MAIL_PASSWORD');
const LOOKBACK_MS = 6 * 60 * 60 * 1000;
const BACKUP_STALE_MS = 48 * 60 * 60 * 1000;

async function sendAlertEmail(subject, text) {
  if (process.env.EMAIL_DRY_RUN === 'true') {
    await db.collection('_emailDryRun').add({to: mailUser.value(), subject, text, createdAt: new Date()});
    return;
  }
  const nodemailer = require('nodemailer');
  const transport = nodemailer.createTransport({service: 'gmail', auth: {user: mailUser.value(), pass: mailPassword.value()}});
  await transport.sendMail({from: mailUser.value(), to: mailUser.value(), subject, text});
}

exports.aiAgentHealthCheck = onSchedule({schedule: 'every 6 hours', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 300, secrets: [mailUser, mailPassword]}, async () => {
  const config = await getConfigData();
  if (!config.enabled || config.modules?.monitoring === false) return;

  const since = new Date(Date.now() - LOOKBACK_MS);
  const recent = await db.collection('aiAgentAuditLog').where('at', '>=', since).get();
  const denied = recent.docs.filter(d => d.data().result === 'denied' || d.data().result?.toString().startsWith('fail')).length;

  const lastBackup = await db.collection('_aiAgentBackupJobs').orderBy('startedAt', 'desc').limit(1).get();
  const lastBackupAt = lastBackup.docs[0]?.data()?.startedAt?.toMillis?.();
  const backupStale = config.modules?.backup !== false && (!lastBackupAt || Date.now() - lastBackupAt > BACKUP_STALE_MS);

  const problems = [];
  if (denied >= 5) problems.push(`${denied} denied/failed AI Agent action(s) in the last 6 hours.`);
  if (backupStale) problems.push('No successful backup export in the last 48 hours.');

  if (problems.length) {
    await sendAlertEmail('AI Admin Agent: issues detected', problems.join('\n'));
  }
  await writeAuditLog({type: 'monitoring', action: 'healthCheck', detail: `denied=${denied} backupStale=${backupStale}`, result: problems.length ? 'issues' : 'ok'});
});
