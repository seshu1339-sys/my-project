'use strict';
// The daily self-test (owner spec F, 17 Nov 2026): plain code, no AI. Each check is {id, name, group, registryIds, run}; run() returns
// nothing when all is well, or throws with what is wrong. A check NEVER touches real data: saves go to _healthTest (deleted right after),
// the photo goes to _healthTest/ in Storage (deleted right after, and not in a folder the photo optimizer watches), and the ad and radius
// checks only read live ads and compute with made-up points.
//
// registryIds are the command-box option IDs (lib/ui/agent_registry_build.dart) that get a red mark while the check fails.
const {distanceKm, radiusCovers} = require('../../radius');

const FETCH_TIMEOUT_MS = 15000;
// A 1x1 PNG: the smallest real photo to upload.
const PIXEL_PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=', 'base64');

/// The sites, from settings/health.urls (one per line) when the admin set them, else the four Firebase sites and locamarket.in.
function siteUrls(project, healthSettings = {}) {
  const own = String(healthSettings.urls || '').split(/\s+/).map(s => s.trim()).filter(s => /^https:\/\//.test(s));
  if (own.length) return own.map(url => ({url, name: url}));
  return [
    {url: `https://${project}.web.app/`, name: 'Customer website (Firebase)', registryIds: ['page.layout', 'page.theme']},
    {url: `https://${project}-admin.web.app/`, name: 'Admin panel site', registryIds: ['page.settings']},
    {url: `https://${project}-vendor.web.app/`, name: 'Vendor web app', registryIds: ['page.tab.vendors']},
    {url: `https://${project}-field.web.app/`, name: 'Staff web app', registryIds: ['page.fieldassistants']},
    {url: 'https://locamarket.in/', name: 'locamarket.in (Hostinger)', registryIds: ['page.layout']},
  ];
}

/// The server functions pinged without a sign-in: a live one answers "sign in first" (401/403) or "bad request" (400); a missing one
/// 404, a broken one 5xx. Only functions that check the sign-in before doing anything are on this list.
const CALLABLES = [
  ['placeOrder', ['page.tab.orders']], ['registerVendor', ['page.tab.vendors']], ['approveVendor', ['page.tab.vendors']],
  ['submitVendorChange', ['page.tab.products']], ['confirmTodaysRates', ['page.tab.products']], ['submitTodaysOffer', ['page.homepromo']],
  ['submitVendorAd', ['page.ads', 'page.rightboxes']], ['decideVendorAd', ['page.ads']], ['assignRightBoxVendor', ['page.rightboxes']],
  ['createComplaint', ['page.tab.complaints']], ['submitStaffVendor', ['page.fieldassistants']], ['staffWorkOverview', ['page.staffwork']],
  ['idReport', ['page.idreport']], ['startRazorpayPayment', ['page.tab.payments']], ['saveVendorOffer', ['page.tab.vendor-offers']],
  ['rateShop', ['page.ratings']], ['reportAbuse', ['page.reports']], ['askAdminAssistant', ['page.aiassistant']],
  ['askAdminSearch', ['page.aiprovider']], ['setAiKey', ['page.aiprovider']], ['reportAppProblems', ['page.apphealth']],
];

async function fetchWithTimeout(fetchImpl, url, init = {}) {
  return fetchImpl(url, {...init, signal: AbortSignal.timeout(FETCH_TIMEOUT_MS), redirect: 'follow'});
}

/// Builds the checks. [deps] = {db, bucket, fetch, project, now} (fakes in the tests).
function buildChecks(deps, healthSettings = {}) {
  const {db, bucket, fetch: fetchImpl, project} = deps;
  const run = deps.runId || `run_${Date.now()}`;
  const checks = [];

  for (const site of siteUrls(project, healthSettings)) {
    checks.push({
      id: `site:${site.url}`, name: `${site.name} opens`, group: 'Pages', registryIds: site.registryIds || [],
      run: async () => {
        const res = await fetchWithTimeout(fetchImpl, site.url);
        if (res.status !== 200) throw Error(`HTTP ${res.status}`);
        const html = await res.text();
        if (!/main\.dart\.js|flutter_bootstrap|flutter\.js/.test(html)) throw Error('The page opened but the app script is missing');
        const script = new URL('main.dart.js', res.url || site.url).toString();
        const js = await fetchWithTimeout(fetchImpl, script, {method: 'HEAD'});
        if (js.status !== 200) throw Error(`main.dart.js: HTTP ${js.status}`);
      },
    });
  }

  for (const [name, registryIds] of CALLABLES) {
    checks.push({
      id: `api:${name}`, name: `Server function ${name} answers`, group: 'Server functions', registryIds,
      run: async () => {
        const res = await fetchWithTimeout(fetchImpl, `https://us-central1-${project}.cloudfunctions.net/${name}`, {
          method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({data: {}}),
        });
        if ([400, 401, 403].includes(res.status)) return;
        if (res.status === 200) return;
        if (res.status === 404) throw Error('Not found: the function is not deployed');
        throw Error(`HTTP ${res.status}`);
      },
    });
  }

  checks.push({
    id: 'save:firestore', name: 'A test record saves, reads back and is deleted', group: 'Saves', registryIds: ['page.settings'],
    run: async () => {
      const ref = db.collection('_healthTest').doc(run);
      await ref.set({test: true, at: new Date(deps.now ?? Date.now())});
      const back = await ref.get();
      await ref.delete();
      if (!back.exists || back.data().test !== true) throw Error('The test record did not read back');
      if ((await ref.get()).exists) throw Error('The test record was not deleted');
    },
  });

  checks.push({
    id: 'save:storage', name: 'A test photo uploads and is deleted', group: 'Saves', registryIds: ['page.productimagelibrary', 'page.rightboxes', 'page.module-itemphotos'],
    run: async () => {
      const file = bucket.file(`_healthTest/${run}.png`);
      await file.save(PIXEL_PNG, {contentType: 'image/png', resumable: false});
      const [exists] = await file.exists();
      await file.delete({ignoreNotFound: true});
      if (!exists) throw Error('The test photo was not stored');
    },
  });

  checks.push({
    id: 'ads:data', name: 'Live ads have a photo or text, a valid place and dates', group: 'Ads', registryIds: ['page.ads', 'page.homepromo', 'page.rightboxes', 'page.tab.promotions'],
    run: async () => {
      const now = deps.now ?? Date.now();
      const bad = [];
      for (const name of ['promotions', 'ads']) {
        const snap = await db.collection(name).limit(300).get();
        for (const d of snap.docs) bad.push(...adProblems(name, d.id, d.data(), now));
      }
      if (bad.length) throw Error(bad.slice(0, 8).join('; ') + (bad.length > 8 ? ` (+${bad.length - 8} more)` : ''));
    },
  });

  checks.push({
    id: 'ads:radius', name: 'Location / radius ads reach the right km', group: 'Ads', registryIds: ['page.settings', 'page.ads'],
    run: async () => {
      // Narsipatnam and points about 5 km and 20 km away.
      const centre = {latitude: 17.6676, longitude: 82.6129, radiusLat: 17.6676, radiusLng: 82.6129, radiusKm: 10};
      const near = [17.7126, 82.6129], far = [17.8476, 82.6129];
      const dNear = distanceKm(centre.latitude, centre.longitude, ...near), dFar = distanceKm(centre.latitude, centre.longitude, ...far);
      if (Math.abs(dNear - 5) > .3 || Math.abs(dFar - 20) > .5) throw Error(`Distance is wrong: ${dNear.toFixed(2)} / ${dFar.toFixed(2)} km`);
      if (!radiusCovers(centre, ...near)) throw Error('An ad 5 km away inside 10 km is not shown');
      if (radiusCovers(centre, ...far)) throw Error('An ad 20 km away outside 10 km is shown');
    },
  });

  checks.push({
    id: 'config:remote', name: 'Android apps can read their design settings (remote config)', group: 'Remote config', registryIds: ['page.androidhome', 'page.layout', 'page.theme'],
    run: async () => {
      const ids = ['business', 'androidHome', 'androidSizes', 'theme', 'design'];
      const docs = await Promise.all(ids.map(id => db.collection('settings').doc(id).get()));
      if (!docs[0].exists) throw Error('settings/business is missing');
      const wrong = [];
      for (const [i, d] of docs.entries()) {
        if (!d.exists) continue;
        for (const [k, v] of Object.entries(d.data())) {
          if (ids[i] === 'androidSizes' && k.includes('__') && v !== '' && v != null && !Number.isFinite(Number(v))) wrong.push(`${ids[i]}.${k}=${v}`);
          if (ids[i] === 'design' && k.endsWith('Color') && v && !/^#?[0-9a-f]{6,8}$/i.test(String(v))) wrong.push(`${ids[i]}.${k}=${v}`);
        }
      }
      if (wrong.length) throw Error(`Unreadable values: ${wrong.slice(0, 6).join(', ')}`);
    },
  });

  return checks;
}

/// What is wrong with one ad document ([] when nothing). Only ads that are live now are checked.
function adProblems(collection, id, d, now = Date.now()) {
  const ms = v => (v?.toMillis ? v.toMillis() : v ? Date.parse(v) : NaN);
  if (d.active === false || d.status === 'rejected' || d.status === 'pending') return [];
  const ends = ms(d.endsAt ?? d.endAt), starts = ms(d.startsAt ?? d.startAt);
  if (Number.isFinite(ends) && ends < now) return [];
  const out = [];
  const label = `${collection}/${id}`;
  if (!d.imageUrl && !d.image && !d.title && !d.text && !d.photoUrl) out.push(`${label}: no photo and no text`);
  if (Number.isFinite(starts) && Number.isFinite(ends) && ends < starts) out.push(`${label}: ends before it starts`);
  const hasPoint = d.latitude != null || d.longitude != null;
  if (hasPoint && (!Number.isFinite(Number(d.latitude)) || !Number.isFinite(Number(d.longitude)) || Math.abs(Number(d.latitude)) > 90 || Math.abs(Number(d.longitude)) > 180)) {
    out.push(`${label}: bad latitude / longitude`);
  }
  if (d.radiusKm != null && d.radiusKm !== '' && !(Number(d.radiusKm) > 0)) out.push(`${label}: radius km is not a number above 0`);
  return out;
}

/// Runs every check (one after another, each timed), never throwing.
async function runChecks(checks, now = () => Date.now()) {
  const results = [];
  for (const c of checks) {
    const start = now();
    try {
      await c.run();
      results.push({id: c.id, name: c.name, group: c.group, registryIds: c.registryIds || [], ok: true, error: '', ms: now() - start});
    } catch (error) {
      results.push({id: c.id, name: c.name, group: c.group, registryIds: c.registryIds || [], ok: false, error: String(error?.message || error).slice(0, 500), ms: now() - start});
    }
  }
  return results;
}

module.exports = {buildChecks, runChecks, adProblems, siteUrls, CALLABLES, PIXEL_PNG};
