'use strict';
// All scheduled work in two Cloud Scheduler jobs (owner, 12 Nov 2026: 13 jobs cost money, only 3 are free; at most 3 may stay).
//
//   every15Minutes  every 15 minutes   post duration (when the admin changed it), expired vendor prices, Quick Add items, Today's
//                                      Offers boxes, ended paid plans, new-offer pushes
//   hourlyTasks     at :20 every hour  by the hour in India:
//                     00:20 staff areas nightly check
//                     03:20 inactive accounts, storage maintenance (photos, exclusive items), Firestore backup (and the backups older
//                           than 7 days are removed by the bucket's lifecycle rule), Mondays the storage usage
//                     08:20 vendor ad summaries
//                     17:20 staff areas last-chance reminder
//                     00:20, 06:20, 12:20, 18:20 AI agent health check (does nothing unless switched on)
//
// Each piece is the old scheduled function's own code (now a plain task(), see task.js), so what each one does is unchanged. One piece
// failing is logged and does not stop the others.
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {defineSecret} = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const {getFirestore} = require('firebase-admin/firestore');
const {applyPostDurationIfChanged} = require('./post-duration');

// The health check emails with the admin mail password.
const mailPassword = defineSecret('ADMIN_MAIL_PASSWORD');

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

/// Runs the pieces one after another; a failure is logged and the next piece still runs. Returns the names that failed.
async function runAll(pieces) {
  const failed = [];
  for (const [name, run] of pieces) {
    try {
      await run();
    } catch (error) {
      failed.push(name);
      logger.error(`Scheduled piece ${name} failed`, {error: error?.stack || String(error)});
    }
  }
  return failed;
}

/// The pieces of the 15-minute job. [tasks] are the old scheduled functions' tasks by name (functions/index.js hands them over, so this
/// file never loads a module itself).
function quarterHourPieces(tasks) {
  return [
    ['postDuration', () => applyPostDurationIfChanged(getFirestore())],
    ...['expireVendorPrices', 'expireQuickItems', 'clearTodaysOffers', 'expirePremiumStatus', 'notifyNewOffers'].map(name => [name, () => tasks[name].run({})]),
  ];
}

/// The pieces due at this hour in India (the job runs at :20 past every hour).
function hourlyPieces(tasks, now = Date.now()) {
  const ist = new Date(now + IST_OFFSET_MS);
  const hour = ist.getUTCHours(), monday = ist.getUTCDay() === 1;
  const names = [];
  if (hour === 0) names.push('staffAreaNightly');
  if (hour === 3) names.push('sweepInactiveAccounts', 'dailyStorageMaintenance', 'aiAgentDailyBackup', ...(monday ? ['weeklyStorageUsage'] : []));
  if (hour === 8) names.push('sendAdSummaries');
  if (hour === 17) names.push('staffAreaLastChance');
  if (hour % 6 === 0) names.push('aiAgentHealthCheck');
  return names.map(name => [name, () => tasks[name].run({})]);
}

const TASK_NAMES = ['expireVendorPrices', 'expireQuickItems', 'clearTodaysOffers', 'expirePremiumStatus', 'notifyNewOffers', 'staffAreaNightly',
  'sweepInactiveAccounts', 'dailyStorageMaintenance', 'aiAgentDailyBackup', 'weeklyStorageUsage', 'sendAdSummaries', 'staffAreaLastChance', 'aiAgentHealthCheck'];

/// The two scheduled functions, given every task by name. A missing task stops the deploy rather than a job silently not running.
function scheduledJobs(tasks) {
  const missing = TASK_NAMES.filter(name => typeof tasks[name]?.run !== 'function');
  if (missing.length) throw Error(`Scheduled tasks missing: ${missing.join(', ')}`);
  return {
    every15Minutes: onSchedule({schedule: 'every 15 minutes', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 540}, async () => {
      await runAll(quarterHourPieces(tasks));
    }),
    hourlyTasks: onSchedule({schedule: '20 * * * *', timeZone: 'Asia/Kolkata', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 540, secrets: [mailPassword]}, async () => {
      await runAll(hourlyPieces(tasks));
    }),
  };
}

module.exports = {scheduledJobs, runAll, quarterHourPieces, hourlyPieces, TASK_NAMES};
