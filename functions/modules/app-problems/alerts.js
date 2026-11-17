'use strict';
// Admin alerts of the app-problems module (owner spec part 1): a problem that happens many times in a short time is written to
// healthAlerts (the admin panel shows a red banner while it is open) and pushed at once to every browser / phone where the admin
// turned on "Alerts on this device" (adminPushTokens/<token>, saved by the admin panel). Push is Firebase Cloud Messaging: free.
//
//   healthAlerts/<id>      {open, type: 'burst' | 'billing', problemId, app, platform, kind, side, message, n, minutes, at}
//   adminPushTokens/<tok>  {uid, at}                                     written by the admin panel (rules: admin only)
const {getMessaging} = require('firebase-admin/messaging');
const {Timestamp} = require('firebase-admin/firestore');

/// The admin panel's address for a notification click (the admin route opens the Health page).
const ADMIN_LINK = process.env.ADMIN_PANEL_URL || 'https://locamarket.in/jyothi9?open=page.health';

/// Sends one notification to every admin device; tokens that no longer work are removed. Never throws: an alert must not break the
/// report that raised it. [send] is the tests' seam.
async function pushAdmins(db, title, body, {send = m => getMessaging().sendEachForMulticast(m), link = ADMIN_LINK} = {}) {
  try {
    const snap = await db.collection('adminPushTokens').limit(30).get();
    const tokens = snap.docs.map(d => d.id);
    if (!tokens.length) return 0;
    const result = await send({tokens, notification: {title, body}, webpush: {fcmOptions: {link}}, data: {type: 'health_alert'}});
    const dead = (result?.responses || []).map((r, i) => (!r.success && /registration-token-not-registered|invalid-argument|invalid-registration-token/.test(String(r.error?.code || '')) ? tokens[i] : null)).filter(Boolean);
    await Promise.all(dead.map(t => db.collection('adminPushTokens').doc(t).delete().catch(() => {})));
    return result?.successCount ?? 0;
  } catch (e) {
    console.warn('Admin push failed', e?.message || e);
    return 0;
  }
}

const APP_NAMES = {customer: 'User app / website', vendor: 'Vendor app', staff: 'Staff app', admin: 'Admin panel'};

/// Opens (or refreshes) the alert of one problem and pushes it to the admin.
async function raiseBurstAlert(db, p, {n, minutes, now = Date.now(), send} = {}) {
  const where = `${APP_NAMES[p.app] || p.app}${p.platform === 'android' ? ' (Android)' : p.platform === 'web' && p.app === 'customer' ? ' (website)' : ''}`;
  await db.collection('healthAlerts').doc(p.id).set({
    open: true, type: 'burst', problemId: p.id, app: p.app, platform: p.platform, kind: p.kind, side: p.side, message: p.message,
    screen: p.screen || '', n, minutes, at: Timestamp.fromMillis(now),
  });
  return pushAdmins(db, `⚠ ${where}: ${n} times in ${minutes} min`, `${p.screen ? `${p.screen}: ` : ''}${p.message}`.slice(0, 180), {send});
}

module.exports = {pushAdmins, raiseBurstAlert, ADMIN_LINK};
