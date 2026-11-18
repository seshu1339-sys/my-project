'use strict';
// Ready answers of the Support Team chat (cost cuts part 4, 18 Nov 2026): stored answers by keywords (English, Telugu, Telugu in English
// letters) before any AI, the right chat only, no tie, not the same answer twice, and the admin's list checked.
const test = require('node:test');
const assert = require('node:assert/strict');
const {DEFAULT_ANSWERS: A, CHAT_KINDS, matchAnswer, replyFor, validateAnswers, norm} = require('./answers');

const id = (text, kind) => matchAnswer(text, A, kind)?.id ?? null;

test('every starting answer is complete, in English and Telugu, and passes the admin check', () => {
  assert.ok(A.length >= 15);
  for (const a of A) {
    assert.ok(a.question.en && a.question.te && a.answer.en && a.answer.te, a.id);
    assert.ok(a.chats.every(c => CHAT_KINDS.includes(c)), a.id);
    assert.ok(a.keywords.length >= 3, a.id);
  }
  assert.equal(validateAnswers(A).length, A.length);
  for (const kind of CHAT_KINDS) assert.ok(A.some(a => a.chats.includes(kind)), `${kind} has ready answers`);
  assert.ok(A.find(a => a.id === 'login').chats.length === 5, 'login help is in every chat');
});

test('the owner\'s questions get their stored answer, in English, Telugu and Telugu in English letters', () => {
  assert.equal(id('What plans are there?', 'vendor'), 'plans');
  assert.equal(id('how much is gold plan', 'vendor'), 'prices');
  assert.equal(id('plan validity?', 'premium'), 'validity');
  assert.equal(id('ప్లాన్ గడువు ఎన్ని రోజులు', 'vendor'), 'validity');
  assert.equal(id('how to add item', 'vendor'), 'add_item');
  assert.equal(id('I want to change price of tomato', 'vendor'), 'change_price');
  assert.equal(id('login avvatledu', 'staff'), 'login');
  assert.equal(id('లాగిన్ కావడం లేదు', 'user'), 'login');
  assert.equal(id('where to buy cheapest onion', 'user'), 'search');
  assert.equal(id('what is my target this month', 'staff'), 'staff_targets');
  assert.equal(id('Plans', 'vendor'), 'plans', 'the button text itself');
});

test('no match, another chat\'s answer, a complaint or a tie: no stored answer (AI or the team answers)', () => {
  assert.equal(id('hello', 'user'), null);
  assert.equal(id('my payment failed money deducted', 'vendor'), null);
  assert.equal(id('What plans are there?', 'user'), null, 'plans are for vendors');
  assert.equal(id('', 'vendor'), null);
  const tie = [
    {id: 'a', chats: ['user'], keywords: ['alpha'], question: {en: 'A'}, answer: {en: 'A'}},
    {id: 'b', chats: ['user'], keywords: ['alpha'], question: {en: 'B'}, answer: {en: 'B'}},
  ];
  assert.equal(matchAnswer('alpha', tie, 'user'), null);
  assert.equal(matchAnswer('What plans are there?', A, 'vendor', {skip: ['plans']}), null, 'not the same answer twice in a chat');
  assert.equal(matchAnswer('plan', [{...A[0], active: false}], 'vendor'), null, 'a switched-off answer');
});

test('the answer comes in the language the person wrote', () => {
  const plans = A.find(a => a.id === 'plans');
  assert.equal(replyFor(plans, 'plans?'), plans.answer.en);
  assert.equal(replyFor(plans, 'ప్లాన్లు ఏమిటి'), plans.answer.te);
  assert.equal(replyFor({answer: {en: 'Only English'}}, 'ప్లాన్'), 'Only English');
  assert.equal(norm('  Plan—PRICE?! '), 'plan price');
});

test('the admin list is checked before it is saved', () => {
  assert.throws(() => validateAnswers('x'), /0 to 60/);
  assert.throws(() => validateAnswers([{id: 'a', chats: [], question: {en: 'Q'}, answer: {en: 'A'}}]), /at least one chat/);
  assert.throws(() => validateAnswers([{id: 'a', chats: ['user'], question: {en: ''}, answer: {en: 'A'}}]), /question \(English\)/);
  assert.throws(() => validateAnswers([{id: 'a', chats: ['user'], question: {en: 'Q'}, answer: {en: ''}}]), /answer \(English\)/);
  assert.throws(() => validateAnswers([{id: 'a', chats: ['user'], question: {en: 'Q'}, answer: {en: 'A'}}, {id: 'a', chats: ['user'], question: {en: 'Q'}, answer: {en: 'A'}}]), /same id/);
  const [clean] = validateAnswers([{id: 'Bad Id!', chats: ['user', 'nobody'], question: {en: ' Q '}, answer: {en: 'A', te: 'ఏ'}, keywords: [' k ', ''], active: false}]);
  assert.deepEqual(clean, {id: 'answer_1', chats: ['user'], keywords: ['k'], order: 1, active: false, question: {en: 'Q', te: ''}, answer: {en: 'A', te: 'ఏ'}});
});
