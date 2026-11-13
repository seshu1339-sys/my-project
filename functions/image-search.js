'use strict';
// Photo search: describeImageForSearch  signed-in user -> a few search words for the product in the picture.
// Uses the same Anthropic key as the Flash chat (ANTHROPIC_API_KEY) and the photo search model (functions/ai-models.js). Nothing is stored.
// Each signed-in person has a daily allowance (settings/business.photoSearchesPerDay, 10 when not set; the admin changes it in Business
// Profile). Past it the app says "try again tomorrow" and Anthropic is not called.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {AI_MODELS, keyIsSet} = require('./ai-models');

const anthropicKey = defineSecret('ANTHROPIC_API_KEY');
const MODEL = AI_MODELS.photoSearch;
const MAX_BASE64 = 4 * 1024 * 1024;
const DEFAULT_PHOTO_SEARCHES_PER_DAY = 10;
const IST_MS = 5.5 * 60 * 60 * 1000;
const PROMPT = 'This photo was taken by a shopper looking for a product or a local service in an Indian town. ' +
  'Reply with ONLY 1 to 3 plain English words naming the product or service (for example "rice", "plumber", "school bag"). ' +
  'No sentence, no punctuation. If nothing sellable is visible, reply exactly: NONE';

/// Picks the image type from the first bytes; the app sends JPEG, PNG or WebP.
function imageType(base64) {
  const head = Buffer.from(base64.slice(0, 16), 'base64');
  if (head[0] === 0xff && head[1] === 0xd8) return 'image/jpeg';
  if (head[0] === 0x89 && head[1] === 0x50) return 'image/png';
  if (head.slice(0, 4).toString() === 'RIFF') return 'image/webp';
  return null;
}

/// Cleans the model's reply into a safe search string ('' when it saw nothing).
function cleanQuery(text) {
  const words = String(text || '').replace(/[^\p{L}\p{N}\s]/gu, ' ').trim().split(/\s+/).filter(Boolean).slice(0, 3);
  const query = words.join(' ').toLowerCase();
  return query === 'none' ? '' : query;
}

/// The admin's daily photo searches per person (1 to 1000), 10 when not set.
function photoSearchLimit(business) {
  const n = Math.round(Number(business?.photoSearchesPerDay));
  return Number.isFinite(n) && n >= 1 && n <= 1000 ? n : DEFAULT_PHOTO_SEARCHES_PER_DAY;
}

/// Takes one of today's photo searches (the Indian day) for [uid]. Returns the limit, or throws "try again tomorrow" when it is used up.
async function takePhotoSearch(db, uid, now = Date.now()) {
  const limit = photoSearchLimit((await db.collection('settings').doc('business').get()).data());
  const day = new Date(now + IST_MS).toISOString().slice(0, 10);
  const ref = db.collection('aiDailyUse').doc(`photo_${uid}_${day}`);
  const allowed = await db.runTransaction(async tx => {
    const count = (await tx.get(ref)).data()?.count ?? 0;
    if (count >= limit) return false;
    tx.set(ref, {key: `photo_${uid}`, day, count: count + 1});
    return true;
  });
  if (!allowed) throw new HttpsError('resource-exhausted', `You have used today's ${limit} photo searches. Please try again tomorrow.`);
  return limit;
}

let client;
/// The Anthropic client, made on first use.
function anthropic() {
  if (!client) {
    const Anthropic = require('@anthropic-ai/sdk').default;
    client = new Anthropic({apiKey: anthropicKey.value()});
  }
  return client;
}

exports.describeImageForSearch = onCall({region: 'us-central1', maxInstances: 5, secrets: [anthropicKey], memory: '256MiB'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const image = request.data && request.data.image;
  if (typeof image !== 'string' || !image || image.length > MAX_BASE64) throw new HttpsError('invalid-argument', 'Send a photo under 3 MB.');
  const type = imageType(image);
  if (!type) throw new HttpsError('invalid-argument', 'Use a JPEG, PNG or WebP photo.');
  if (!keyIsSet(anthropicKey.value())) throw new HttpsError('failed-precondition', 'Photo search is not set up yet.');
  const db = getFirestore();
  await takePhotoSearch(db, request.auth.uid);
  let response;
  try {
    response = await anthropic().messages.create({
      model: MODEL, max_tokens: 64,
      // A short label: no thinking needed (Haiku 5.5 accepts thinking off at its default effort).
      thinking: {type: 'disabled'},
      messages: [{role: 'user', content: [
        {type: 'image', source: {type: 'base64', media_type: type, data: image}},
        {type: 'text', text: PROMPT},
      ]}],
    });
  } catch (error) {
    console.error('Photo search model error', error.status ?? error.name);
    throw new HttpsError('unavailable', 'Photo search is busy. Try again.');
  }
  const text = response.stop_reason === 'refusal' ? '' : response.content.find(block => block.type === 'text')?.text;
  try {
    await db.collection('aiCallLog').add({
      feature: 'photo_search', model: MODEL, uid: request.auth.uid, stopReason: response.stop_reason ?? '',
      inputTokens: response.usage?.input_tokens ?? 0, outputTokens: response.usage?.output_tokens ?? 0, at: Timestamp.now(),
    });
  } catch (error) { console.warn('AI call not logged', error.message); }
  return {query: cleanQuery(text)};
});
exports._test = {imageType, cleanQuery, photoSearchLimit, takePhotoSearch, DEFAULT_PHOTO_SEARCHES_PER_DAY};
