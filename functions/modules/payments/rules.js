'use strict';
// Payment verification: the pure rules, no database. Every bank detail is configuration, so filling them in needs no code change.
//
// Until the HDFC account exists these are placeholders. Any value starting with XX counts as "not filled in": while one remains,
// no SMS is matched, nothing activates by itself and vendors see "Payments will open soon".
const crypto = require('node:crypto');

const IST = 19800000;
const HOUR_MS = 3600000;
const MAX_SMS = 1000;

const DEFAULT_CONFIG = Object.freeze({
  accountName: 'XX-ACCOUNT-NAME',
  accountNumber: 'XX-ACCOUNT-NUMBER',
  ifsc: 'XX-IFSC',
  upiId: 'XX-UPI-ID',
  smsSenders: ['XX-SENDER-ID'],
  smsPatterns: [{credit: 'XX-CREDIT-WORDS', amount: 'XX-AMOUNT-REGEX', paymentId: 'XX-PAYMENT-ID-REGEX'}],
  windowHours: 3,
  dailyScreenshots: 5,
});

const isPlaceholder = value => typeof value !== 'string' || value.trim() === '' || /^XX/.test(value.trim());

function compiles(pattern) {
  try { new RegExp(pattern, 'i'); return true; } catch { return false; }
}

/// True when the admin filled in everything and every pattern is a valid regular expression.
function configReady(config) {
  const texts = [config.accountName, config.accountNumber, config.ifsc, config.upiId];
  const senders = config.smsSenders ?? [], patterns = config.smsPatterns ?? [];
  if (texts.some(isPlaceholder) || senders.length === 0 || senders.some(isPlaceholder) || patterns.length === 0) return false;
  return patterns.every(p => [p.credit, p.amount, p.paymentId].every(text => !isPlaceholder(text) && compiles(text)));
}

const text = (value, max) => (typeof value === 'string' ? value.trim().slice(0, max) : '');

/// What the admin may save. Placeholders are allowed; broken patterns are not, so a typing slip never silently stops matching.
function validateConfig(data) {
  const smsSenders = Array.isArray(data.smsSenders) ? data.smsSenders.map(s => text(s, 40)).filter(Boolean) : [];
  const smsPatterns = (Array.isArray(data.smsPatterns) ? data.smsPatterns : []).map(p => ({credit: text(p?.credit, 300), amount: text(p?.amount, 300), paymentId: text(p?.paymentId, 300)}));
  if (smsSenders.length === 0 || smsSenders.length > 10) throw new Error('Enter 1 to 10 SMS sender IDs.');
  if (smsPatterns.length === 0 || smsPatterns.length > 10) throw new Error('Enter 1 to 10 SMS patterns.');
  for (const pattern of smsPatterns) {
    for (const [name, value] of Object.entries(pattern)) {
      if (!value) throw new Error(`Fill in the ${name} pattern.`);
      if (!isPlaceholder(value) && !compiles(value)) throw new Error(`The ${name} pattern is not a valid regular expression.`);
    }
  }
  const windowHours = data.windowHours, dailyScreenshots = data.dailyScreenshots;
  if (!Number.isInteger(windowHours) || windowHours < 1 || windowHours > 24) throw new Error('The window must be 1 to 24 hours.');
  if (!Number.isInteger(dailyScreenshots) || dailyScreenshots < 1 || dailyScreenshots > 50) throw new Error('The screenshot limit must be 1 to 50 a day.');
  return {
    accountName: text(data.accountName, 100), accountNumber: text(data.accountNumber, 40), ifsc: text(data.ifsc, 20), upiId: text(data.upiId, 100),
    smsSenders, smsPatterns, windowHours, dailyScreenshots,
  };
}

/// Only what a vendor needs in order to pay. No patterns, no sender IDs.
function publicDetails(config) {
  return {ready: configReady(config), accountName: config.accountName, accountNumber: config.accountNumber, ifsc: config.ifsc, upiId: config.upiId};
}

/// A sender such as AD-HDFCBK-S ends or contains the bank's id; the operator prefix changes, so the id only has to be inside it.
function senderAllowed(sender, config) {
  const from = text(sender, 40).toUpperCase();
  return from !== '' && (config.smsSenders ?? []).some(allowed => !isPlaceholder(allowed) && from.includes(allowed.toUpperCase()));
}

const paymentIdValid = id => typeof id === 'string' && /^[A-Za-z0-9]{6,40}$/.test(id);

/// The payment id and amount of a credit SMS, or null. Only these two leave this function; the SMS text itself is never stored.
function parseSms(body, config) {
  const message = text(body, MAX_SMS);
  for (const pattern of config.smsPatterns ?? []) {
    if (isPlaceholder(pattern.credit) || isPlaceholder(pattern.amount) || isPlaceholder(pattern.paymentId)) continue;
    if (!new RegExp(pattern.credit, 'i').test(message)) continue;
    const amount = Number(message.match(new RegExp(pattern.amount, 'i'))?.[1]?.replace(/,/g, ''));
    const paymentId = message.match(new RegExp(pattern.paymentId, 'i'))?.[1]?.toUpperCase();
    if (Number.isFinite(amount) && amount > 0 && paymentIdValid(paymentId)) return {paymentId, amount};
  }
  return null;
}

/// A date and time read from a screenshot (Indian time) as milliseconds, or null.
function istMillis(date, time) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date ?? '') || !/^\d{2}:\d{2}$/.test(time ?? '')) return null;
  const ms = Date.parse(`${date}T${time}:00+05:30`);
  return Number.isFinite(ms) ? ms : null;
}

const sameMoney = (a, b) => Math.round(a * 100) === Math.round(b * 100);

/// Why a screenshot cannot go on to SMS checking, or '' when it can.
function claimProblem(claim, request, windowHours, now) {
  if (!claim?.readable || !paymentIdValid(claim.paymentId) || !Number.isFinite(claim.amount)) return 'The screenshot could not be read.';
  if (!sameMoney(claim.amount, request.amount)) return `The amount paid (₹${claim.amount}) differs from the price (₹${request.amount}).`;
  const paidAt = istMillis(claim.date, claim.time);
  if (paidAt === null) return 'The payment date or time could not be read.';
  if (paidAt > now + HOUR_MS) return 'The payment time is in the future.';
  const asked = request.createdAt?.toMillis?.() ?? 0;
  if (paidAt < asked - windowHours * HOUR_MS) return 'The payment was made before this plan was chosen.';
  return '';
}

/// Does a stored SMS confirm this claim? Same amount, and close in time.
function smsConfirms(sms, claimedPaidAt, amount, windowHours) {
  return sameMoney(sms.amount, amount) && Math.abs(sms.smsAt - claimedPaidAt) <= windowHours * HOUR_MS;
}

/// Compares in constant time, so the SMS endpoint's token cannot be guessed a letter at a time.
function tokenMatches(header, token) {
  const given = crypto.createHash('sha256').update(String(header)).digest();
  const wanted = crypto.createHash('sha256').update(`Bearer ${token}`).digest();
  return token.length > 0 && crypto.timingSafeEqual(given, wanted);
}

module.exports = {tokenMatches, IST, HOUR_MS, DEFAULT_CONFIG, isPlaceholder, configReady, validateConfig, publicDetails, senderAllowed, paymentIdValid, parseSms, istMillis, sameMoney, claimProblem, smsConfirms};
