'use strict';
// Ready answers of the Support Team chat (owner, 18 Nov 2026: cost cuts part 4). No AI and no database here, so the tests check it
// without a server:
//   * the ready-question buttons the chat shows first (each answer belongs to some of the five chats);
//   * a typed question is matched to a stored answer by its keywords (English, Telugu and Telugu in English letters) before any AI;
//   * the admin's list is checked before it is saved (flashAnswers/main {items}).
const DEFAULT_ANSWERS = require('./default-answers.json').answers;

const CHAT_KINDS = ['user', 'vendor', 'premium', 'provider', 'staff'];
const MAX_ANSWERS = 60;
const MAX_KEYWORDS = 30;
// A typed question needs at least this much keyword match (one English keyword of 4 letters, or one short Telugu word).
const MIN_SCORE = 4;
const TELUGU = /[ఀ-౿]/;

/// Lower case words: English letters and digits, and Telugu letters with their vowel signs.
const norm = text => String(text ?? '').toLowerCase().replace(/[^a-z0-9ఀ-౿]+/g, ' ').trim();

/// How strongly [keyword] is in the text: 0 when it is not. Telugu words change their endings, so a Telugu keyword counts anywhere
/// inside a word (and twice its length: Telugu letters carry more); an English one must be a whole word or the start of one ("plans").
function keywordScore(text, words, keyword) {
  const k = norm(keyword);
  if (!k) return 0;
  if (TELUGU.test(k)) return text.includes(k) ? k.length * 2 : 0;
  if (k.includes(' ')) return ` ${text} `.includes(` ${k} `) ? k.length : 0;
  return words.some(w => w === k || (k.length >= 4 && w.startsWith(k))) ? k.length : 0;
}

/// The stored answer for a typed [text] in the chat [kind], or null (then AI may answer). Answers in [skip] were already given in this
/// chat: a person asking again needs more than the same words. A tie between two answers is no match.
function matchAnswer(text, answers, kind, {skip = []} = {}) {
  const t = norm(text);
  if (!t) return null;
  const words = t.split(' ');
  let best = null, bestScore = 0, second = 0;
  for (const a of answers) {
    if (a.active === false || !Array.isArray(a.chats) || !a.chats.includes(kind)) continue;
    const asked = [a.question?.en, a.question?.te].map(norm).filter(Boolean).includes(t);
    let score = asked ? 1000 : 0;
    for (const k of a.keywords || []) score += keywordScore(t, words, k);
    if (score > bestScore) {
      second = bestScore;
      bestScore = score;
      best = a;
    } else if (score > second) {
      second = score;
    }
  }
  if (!best || bestScore < MIN_SCORE || bestScore === second || skip.includes(best.id)) return null;
  return best;
}

/// The answer in the person's language: Telugu when they wrote Telugu letters and there is a Telugu answer.
const replyFor = (answer, text) => (TELUGU.test(String(text ?? '')) && answer.answer?.te ? answer.answer.te : answer.answer?.en || answer.answer?.te || '');

/// The admin's list, checked: an error for anything wrong, else the clean list.
function validateAnswers(items) {
  if (!Array.isArray(items) || items.length > MAX_ANSWERS) throw Error(`Keep 0 to ${MAX_ANSWERS} ready answers.`);
  const ids = new Set();
  const text = (value, max, what, required) => {
    const v = typeof value === 'string' ? value.trim() : '';
    if (required && !v) throw Error(`Write the ${what}.`);
    if (v.length > max) throw Error(`Keep the ${what} under ${max} letters.`);
    return v;
  };
  return items.map((a, i) => {
    const id = typeof a?.id === 'string' && /^[a-z0-9_-]{1,40}$/.test(a.id) ? a.id : `answer_${i + 1}`;
    if (ids.has(id)) throw Error(`Two ready answers have the same id: ${id}.`);
    ids.add(id);
    const chats = Array.isArray(a?.chats) ? [...new Set(a.chats.filter(c => CHAT_KINDS.includes(c)))] : [];
    if (!chats.length) throw Error(`Choose at least one chat for "${a?.question?.en || id}".`);
    const keywords = (Array.isArray(a?.keywords) ? a.keywords : []).map(k => String(k ?? '').trim()).filter(Boolean);
    if (keywords.length > MAX_KEYWORDS || keywords.some(k => k.length > 40)) throw Error(`Keep at most ${MAX_KEYWORDS} keywords of 40 letters for "${a?.question?.en || id}".`);
    return {
      id, chats, keywords,
      order: Number.isInteger(a?.order) ? a.order : i + 1,
      active: a?.active !== false,
      question: {en: text(a?.question?.en, 150, 'question (English)', true), te: text(a?.question?.te, 150, 'question (Telugu)', false)},
      answer: {en: text(a?.answer?.en, 1500, 'answer (English)', true), te: text(a?.answer?.te, 1500, 'answer (Telugu)', false)},
    };
  });
}

module.exports = {DEFAULT_ANSWERS, CHAT_KINDS, MIN_SCORE, norm, keywordScore, matchAnswer, replyFor, validateAnswers};
