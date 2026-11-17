'use strict';
// Pure rules of the app-problems module (owner spec "AI Agent + Health System", 17 Nov 2026, parts 1 and 2). No Firebase here, so
// the tests check them without a server.
//
//   * which side a problem is on: USER (location off, no internet, permission, session, missing field...), DEVICE (it happens only on
//     certain phone models or Android versions) or OUR (server, code bug, slow API, crash);
//   * the burst window: the same problem many times in a short time alerts the admin at once (default 6 times in 60 minutes);
//   * the phone model and the Android version of a device string, as safe map keys.

const SIDES = ['user', 'device', 'our'];

/// The admin's limits (settings/health), each kept inside a safe range.
function healthConfig(d = {}) {
  const int = (v, def, min, max) => {
    const n = Math.round(Number(v));
    return Number.isFinite(n) && n >= min && n <= max ? n : def;
  };
  const sides = String(d.burstSides ?? 'our,device').split(',').map(s => s.trim()).filter(s => SIDES.includes(s));
  return {
    burstCount: int(d.burstCount, 6, 2, 1000),
    burstMinutes: int(d.burstMinutes, 60, 5, 1440),
    burstSides: sides.length ? sides : ['our', 'device'],
  };
}

/// A map key from a free text: no dots, slashes or other characters a Firestore field path cannot hold; at most 60 characters.
const keyOf = value => String(value || 'unknown').replace(/[.~/\\[\]*`$#]/g, '_').replace(/\s+/g, ' ').trim().slice(0, 60) || 'unknown';

/// "Xiaomi Redmi 9 (Android 11)" -> {model: 'Xiaomi Redmi 9', os: 'Android 11'}; a browser string stays the model.
function deviceParts(device, os = '') {
  const m = /^(.*?)\s*\(([^)]*)\)\s*$/.exec(String(device || ''));
  const model = keyOf(m ? m[1] : device);
  return {model, os: keyOf(os || (m ? m[2] : '') || 'unknown')};
}

/// The side of one problem. The app labels USER causes itself (it knows location is off or the internet is down). Everything else
/// is OUR side, unless the people it happens to are almost all on one phone model or one Android version: then it is DEVICE side.
/// [devices] and [oses] are the counts per model / version after this report, [users] how many different people had it.
function sideOf({clientSide, users = 0, devices = {}, oses = {}}) {
  if (clientSide === 'user') return 'user';
  const total = Object.values(devices).reduce((a, b) => a + b, 0);
  if (users >= 3 && total >= 3) {
    const top = counts => Math.max(0, ...Object.values(counts)) / Math.max(1, Object.values(counts).reduce((a, b) => a + b, 0));
    const fewModels = Object.keys(devices).length <= 2 && top(devices) >= 0.8;
    // One Android version for (nearly) every case, across different phone models.
    const known = Object.fromEntries(Object.entries(oses).filter(([k]) => k !== 'unknown'));
    const oneVersion = Object.keys(known).length >= 1 && top(known) >= 0.9 && Object.keys(devices).length >= 2;
    if (fewModels || oneVersion) return 'device';
  }
  return 'our';
}

/// The burst after [n] more reports at [now]: a new window when the last one is older than [minutes]. [alert] is true exactly once
/// per window, when the count reaches the admin's [count].
function nextBurst(prev, n, now, {burstCount, burstMinutes}) {
  const start = prev?.start != null ? Number(prev.start) : null;
  const same = start != null && now - start < burstMinutes * 60000;
  const count = (same ? Number(prev.n) || 0 : 0) + n;
  const alerted = same && prev.alerted === true;
  const alert = !alerted && count >= burstCount;
  return {burst: {start: same ? start : now, n: count, alerted: alerted || alert}, alert};
}

/// Most affected people first, then most errors, then newest (the Health and App Health pages, and the admin AI Agent).
const byImpact = (a, b) => (b.users || 0) - (a.users || 0) || (b.count || 0) - (a.count || 0) || (b.lastAtMs || 0) - (a.lastAtMs || 0);

module.exports = {SIDES, healthConfig, keyOf, deviceParts, sideOf, nextBurst, byImpact};
