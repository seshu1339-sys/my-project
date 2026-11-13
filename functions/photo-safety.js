'use strict';
// Photo safety check (owner, 13 Nov 2026), with Claude Haiku 5.5 (the photo model, functions/ai-models.js). A photo is refused only
// when it clearly shows one of: illegal drugs, guns or other weapons, alcohol, cigarettes or tobacco, adult (sexual) content.
// A photo that also exists on Google is never a reason to refuse (the admin's Google check stays a note only).
// Used by the Auto Approval of registrations (vendors, service providers) and by item and Today's Offer photos.
//   verdict 'safe'     nothing of the five
//   verdict 'unsafe'   one or more of the five (categories says which)
//   verdict 'unknown'  could not check (no AI key yet, the day's checks used up, an error): never an automatic approval or refusal;
//                      the record waits for the admin as before
// A daily allowance for all checks together (settings/business.photoSafetyChecksPerDay, 300 when not set) keeps the cost small.
const {defineSecret} = require('firebase-functions/params');
const {getStorage} = require('firebase-admin/storage');
const {Timestamp} = require('firebase-admin/firestore');
const {AI_MODELS, keyIsSet} = require('./ai-models');

const anthropicKey = defineSecret('ANTHROPIC_API_KEY');
const CATEGORIES = ['drugs', 'weapons', 'alcohol', 'tobacco', 'adult'];
const LABELS = {drugs: 'drugs', weapons: 'guns or weapons', alcohol: 'alcohol', tobacco: 'cigarettes or tobacco', adult: 'adult content'};
const DEFAULT_CHECKS_PER_DAY = 300;
const MAX_BYTES = 4 * 1024 * 1024;
const IST_MS = 5.5 * 60 * 60 * 1000;
const PROMPT = 'This photo was uploaded to LOCAMARKET, a marketplace of local shops and service providers in India. Look only for these ' +
  'five things, shown clearly in the photo: "drugs" (illegal drugs or drug equipment), "weapons" (guns, pistols, rifles, swords or ' +
  'other weapons; ordinary kitchen knives and tools are not weapons), "alcohol" (bottles, cans or glasses of beer, wine or liquor), ' +
  '"tobacco" (cigarettes, beedis, cigars, gutka, tobacco packets or vapes), "adult" (nudity or sexual content). People, shops, food, ' +
  'goods, logos, text and photos taken from the internet are all fine. Say which of the five are clearly shown (none when none).';
const FORMAT = {
  type: 'json_schema',
  schema: {
    type: 'object',
    properties: {found: {type: 'array', items: {type: 'string', enum: CATEGORIES}}, note: {type: 'string'}},
    required: ['found', 'note'],
    additionalProperties: false,
  },
};

const mediaType = (bytes, contentType) => {
  if (/^image\/(jpeg|png|webp|gif)$/.test(contentType || '')) return contentType;
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return 'image/jpeg';
  if (bytes[0] === 0x89 && bytes[1] === 0x50) return 'image/png';
  if (bytes.slice(0, 4).toString() === 'RIFF') return 'image/webp';
  return null;
};

function checksPerDay(business) {
  const n = Math.round(Number(business?.photoSafetyChecksPerDay));
  return Number.isFinite(n) && n >= 1 && n <= 100000 ? n : DEFAULT_CHECKS_PER_DAY;
}

/// One of the day's checks (all photos together). False when the day's number is used up.
async function takeCheck(db, now) {
  const limit = checksPerDay((await db.collection('settings').doc('business').get()).data());
  const day = new Date(now + IST_MS).toISOString().slice(0, 10);
  const ref = db.collection('aiDailyUse').doc(`photo_safety_${day}`);
  return db.runTransaction(async tx => {
    const count = (await tx.get(ref)).data()?.count ?? 0;
    if (count >= limit) return false;
    tx.set(ref, {key: 'photo_safety', day, count: count + 1});
    return true;
  });
}

let client;
function anthropic() {
  if (!client) {
    const Anthropic = require('@anthropic-ai/sdk').default;
    client = new Anthropic({apiKey: anthropicKey.value()});
  }
  return client;
}

/// Checks photo bytes. [makeClient] is replaced in the tests (no real AI call there).
async function checkBytes(db, bytes, contentType, {feature = 'photo_safety', uid = '', makeClient, now = Date.now()} = {}) {
  const type = mediaType(bytes, contentType);
  if (!type || !bytes.length || bytes.length > MAX_BYTES) return {verdict: 'unknown', categories: [], note: 'The photo could not be read.'};
  if (!makeClient && !keyIsSet(process.env.ANTHROPIC_API_KEY)) return {verdict: 'unknown', categories: [], note: 'The photo check is not set up yet.'};
  if (!(await takeCheck(db, now))) return {verdict: 'unknown', categories: [], note: "Today's photo checks are used up."};
  let response;
  try {
    response = await (makeClient || anthropic)().messages.create({
      model: AI_MODELS.photoSearch, max_tokens: 300,
      thinking: {type: 'disabled'},
      output_config: {effort: 'low', format: FORMAT},
      messages: [{role: 'user', content: [{type: 'image', source: {type: 'base64', media_type: type, data: Buffer.from(bytes).toString('base64')}}, {type: 'text', text: PROMPT}]}],
    });
  } catch (error) {
    console.warn('Photo safety check failed', error.status ?? error.name);
    return {verdict: 'unknown', categories: [], note: 'The photo check is busy.'};
  }
  try {
    await db.collection('aiCallLog').add({feature, model: AI_MODELS.photoSearch, uid, stopReason: response.stop_reason ?? '',
      inputTokens: response.usage?.input_tokens ?? 0, outputTokens: response.usage?.output_tokens ?? 0, at: Timestamp.fromMillis(now)});
  } catch { /* the log never fails the check */ }
  if (response.stop_reason !== 'end_turn') return {verdict: 'unknown', categories: [], note: 'The photo could not be checked.'};
  try {
    const parsed = JSON.parse(response.content.find(b => b.type === 'text')?.text || '{}');
    const categories = [...new Set((parsed.found || []).filter(c => CATEGORIES.includes(c)))];
    return {verdict: categories.length ? 'unsafe' : 'safe', categories, note: String(parsed.note || '').slice(0, 300)};
  } catch {
    return {verdict: 'unknown', categories: [], note: 'The photo could not be checked.'};
  }
}

/// Checks a photo in Cloud Storage by its path.
async function checkStoredPhoto(db, path, options = {}) {
  try {
    const file = getStorage().bucket().file(path);
    const [[metadata], [bytes]] = await Promise.all([file.getMetadata(), file.download()]);
    return checkBytes(db, bytes, metadata.contentType, options);
  } catch (error) {
    console.warn('Photo for the safety check not read', error.message);
    return {verdict: 'unknown', categories: [], note: 'The photo could not be read.'};
  }
}

/// "The photo shows alcohol and cigarettes or tobacco": the reason a refused photo gives.
const unsafeReason = categories => `The photo shows ${categories.map(c => LABELS[c] || c).join(' and ')}, which LOCAMARKET does not allow. Upload another photo.`;

/// Several photos: the worst verdict wins (one unsafe photo refuses; one unknown means the admin decides).
async function checkStoredPhotos(db, paths, options = {}) {
  const results = [];
  for (const path of paths.filter(Boolean)) results.push({path, ...(await checkStoredPhoto(db, path, options))});
  const unsafe = results.filter(r => r.verdict === 'unsafe');
  if (unsafe.length) return {verdict: 'unsafe', categories: [...new Set(unsafe.flatMap(r => r.categories))], results};
  if (results.some(r => r.verdict === 'unknown') || !results.length) return {verdict: 'unknown', categories: [], results};
  return {verdict: 'safe', categories: [], results};
}

module.exports = {anthropicKey, CATEGORIES, checkBytes, checkStoredPhoto, checkStoredPhotos, unsafeReason, checksPerDay, DEFAULT_CHECKS_PER_DAY};
