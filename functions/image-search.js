'use strict';
// Photo search: describeImageForSearch  signed-in user -> a few search words for the product in the picture.
// Uses the same Anthropic key as the Flash chat (ANTHROPIC_API_KEY). Nothing is stored.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');

const anthropicKey = defineSecret('ANTHROPIC_API_KEY');
const MODEL = 'claude-haiku-5-5';
const MAX_BASE64 = 4 * 1024 * 1024;
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

exports.describeImageForSearch = onCall({region: 'us-central1', maxInstances: 5, secrets: [anthropicKey], memory: '256MiB'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const image = request.data && request.data.image;
  if (typeof image !== 'string' || !image || image.length > MAX_BASE64) throw new HttpsError('invalid-argument', 'Send a photo under 3 MB.');
  const type = imageType(image);
  if (!type) throw new HttpsError('invalid-argument', 'Use a JPEG, PNG or WebP photo.');
  if (!anthropicKey.value()) throw new HttpsError('failed-precondition', 'Photo search is not set up yet.');
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {'content-type': 'application/json', 'x-api-key': anthropicKey.value(), 'anthropic-version': '2023-06-01'},
    body: JSON.stringify({
      model: MODEL, max_tokens: 30,
      messages: [{role: 'user', content: [
        {type: 'image', source: {type: 'base64', media_type: type, data: image}},
        {type: 'text', text: PROMPT},
      ]}],
    }),
  });
  if (!response.ok) {
    console.error('Photo search model error', response.status);
    throw new HttpsError('unavailable', 'Photo search is busy. Try again.');
  }
  const json = await response.json();
  return {query: cleanQuery(json && json.content && json.content[0] && json.content[0].text)};
});
exports._test = {imageType, cleanQuery};
