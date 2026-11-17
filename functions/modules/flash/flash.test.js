const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const R = require('./rules');
const {askFlash, readAnswer, FORMAT} = require('./answer');
const {readTicket, readTriage, FORMAT: TRIAGE_FORMAT} = require('./triage');
const S = require('./store');
const user = require('./user/chat');
const vendor = require('./vendor/chat');
const staff = require('./staff/chat');
const premium = require('./premium/chat');
const provider = require('./provider/chat');
const {SONNET, HAIKU} = require('../ai-core');

const chats = {user, vendor, premium, provider, staff};
const NOW = Date.parse('2026-11-02T10:00:00+05:30');
const HOUR = 3600000;
const reply = (answer, stop = 'end_turn') => ({stop_reason: stop, content: [{type: 'text', text: JSON.stringify(answer)}], usage: {input_tokens: 100, output_tokens: 20}});
const SAID = {reply: 'Your order is confirmed by the shop.', outcome: 'answered', summary: ''};
const TEAM = {reply: '', outcome: 'needs_team', summary: 'Wants a refund'};

test('the five chats are separate, with the categories of the promo-video spec', () => {
  assert.deepEqual(user.categories, ['Search & shops', 'Offers', 'Services', 'App', 'Orders', 'Other']);
  assert.deepEqual(vendor.categories, ['Login', 'Plans & prices', 'Items & photos', 'Offers', 'Payment', 'Shop', 'Other']);
  assert.deepEqual(premium.categories, ['My plan', 'My stats', 'Ads & offers', 'Wholesale', 'Items & prices', 'Payment', 'Other']);
  assert.deepEqual(provider.categories, ['Login', 'My listing', 'Charge per hour', 'App', 'Other']);
  assert.deepEqual(staff.categories, ['My area', 'Targets', 'Missed days', 'Adding offers', 'Terms', 'Account', 'App', 'Other']);
  const all = [user, vendor, premium, provider, staff];
  for (const field of ['kind', 'collection', 'rules', 'helpField']) assert.equal(new Set(all.map(c => c[field])).size, 5, field);
  // Owner, 13 Nov 2026: every Flash chat uses Claude Haiku 5.5 (functions/ai-models.js); the Premium chat gets more effort instead.
  assert.equal(premium.model, HAIKU, 'the advanced chat uses the chat model (Haiku)');
  assert.equal(premium.effort, 'medium');
  assert.equal(premium.priority, true, 'and comes first in the Support Inbox');
  for (const c of [user, vendor, provider, staff]) assert.equal(c.model, undefined, c.kind);
});

test('nothing that talks to a person can read tickets', () => {
  for (const file of ['answer.js', 'user/chat.js', 'vendor/chat.js', 'vendor/facts.js', 'premium/chat.js', 'provider/chat.js', 'staff/chat.js']) {
    assert.equal(/flashTickets|flashTicketTriage/.test(readFileSync(join(__dirname, file), 'utf8')), false, file);
  }
});

test('the vendor chat reads payments only from the payment documents, and the other chats never do', () => {
  const source = name => readFileSync(join(__dirname, name), 'utf8');
  assert.match(source('vendor/facts.js'), /collection\('paymentRequests'\)/);
  for (const banned of ['paymentSms', 'paymentIds', 'paymentBankConfig']) {
    for (const name of ['vendor/chat.js', 'vendor/facts.js', 'premium/chat.js']) assert.equal(source(name).includes(banned), false, `${name} ${banned}`);
  }
  for (const name of ['user/chat.js', 'staff/chat.js', 'provider/chat.js']) assert.equal(source(name).includes('paymentRequests'), false, name);
});

test('a ticket gets the fixed 24-hour reply, in Telugu for Telugu', () => {
  assert.match(R.ticketReply('my order is late'), /within 24 hours/);
  assert.match(R.ticketReply('నా ఆర్డర్ రాలేదు'), /ఇరవై నాలుగు గంటల్లో/);
});

test('a message must have text and not be very long', () => {
  assert.equal(R.cleanText('  hello '), 'hello');
  assert.throws(() => R.cleanText('   '), /Type a message/);
  assert.throws(() => R.cleanText(5), /Type a message/);
  assert.throws(() => R.cleanText('x'.repeat(R.TEXT_MAX + 1)), /under/);
});

test('the daily limit starts at 30 and the admin can set it', () => {
  assert.equal(R.DEFAULT_CONFIG.dailyMessages, 30);
  assert.equal(R.validateConfig({dailyMessages: 10}).dailyMessages, 10);
  assert.throws(() => R.validateConfig({dailyMessages: 0}), /daily limit/);
  assert.throws(() => R.validateConfig({dailyMessages: '30'}), /daily limit/);
  assert.throws(() => R.validateConfig({dailyMessages: 30, helpUser: 'x'.repeat(4001)}), /help text/);
});

test('the model sees only the person and Flash, starting with the person', () => {
  const messages = [{role: 'flash', text: 'a'}, {role: 'user', text: 'b'}, {role: 'admin', text: 'secret'}, {role: 'flash', text: 'c'}];
  assert.deepEqual(R.historyFor(messages), [{role: 'user', content: 'b'}, {role: 'assistant', content: 'c'}]);
  const long = Array.from({length: 45}, (_, i) => ({role: i % 2 ? 'flash' : 'user', text: `${i}`}));
  const history = R.historyFor(long);
  assert.ok(history.length <= 20);
  assert.equal(history[0].role, 'user');
});

test('only a clean answer from Haiku counts', () => {
  assert.deepEqual(readAnswer(reply(SAID)), {needsTeam: false, reply: SAID.reply, summary: ''});
  assert.deepEqual(readAnswer(reply(TEAM)), {needsTeam: true, reply: '', summary: 'Wants a refund'});
  assert.equal(readAnswer(reply(SAID, 'refusal')), null);
  assert.equal(readAnswer(reply(SAID, 'max_tokens')), null);
  assert.equal(readAnswer(reply({...SAID, reply: '  '})), null);
  assert.equal(readAnswer(reply({...SAID, outcome: 'done'})), null);
  assert.equal(readAnswer({stop_reason: 'end_turn', content: [{type: 'text', text: 'not json'}]}), null);
  assert.equal(readAnswer({stop_reason: 'end_turn', content: []}), null);
  assert.equal(FORMAT.schema.additionalProperties, false);
});

test('the Haiku request has no tools, no fallback and no prefill', async () => {
  let body;
  const client = {messages: {create: async sent => { body = sent; return reply(SAID); }}};
  await askFlash(client, {rules: 'rules', help: 'help', facts: {a: 1}, history: [{role: 'user', content: 'hi'}]});
  assert.equal(body.model, 'claude-haiku-5-5');
  assert.equal(body.tools, undefined);
  assert.equal(body.fallbacks, undefined);
  assert.equal(body.messages.at(-1).role, 'user');
  assert.match(body.system, /FACTS:\n\{"a":1\}/);
});

test('only a clean reading from Sonnet counts', () => {
  const good = {type: 'payment', urgency: 'high', suggestion: 'Check the bank first.'};
  assert.deepEqual(readTriage(reply(good)), good);
  assert.equal(readTriage(reply(good, 'refusal')), null);
  assert.equal(readTriage(reply({...good, urgency: 'huge'})), null);
  assert.equal(readTriage(reply({...good, suggestion: ''})), null);
  assert.equal(TRIAGE_FORMAT.schema.additionalProperties, false);
});

test('Sonnet is given one ticket and no tools', async () => {
  let body;
  const client = {messages: {create: async sent => { body = sent; return reply({type: 'order', urgency: 'low', suggestion: 'Ask the shop.'}); }}};
  await readTicket(client, {kind: 'user', category: 'Orders', summary: '', text: 'late order'});
  assert.equal(body.model, 'claude-sonnet-5-5');
  assert.equal(body.tools, undefined);
  assert.equal(body.messages.length, 1);
  assert.match(body.messages[0].content, /late order/);
});

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
let seq = 0;
const fresh = name => `flash-${name}-${Date.now()}-${++seq}`;
const person = (name = 'person') => ({uid: fresh(name), email: 'someone@example.com'});
const model = (answer = SAID, stop) => {
  const calls = [];
  return {calls, client: () => ({messages: {create: async body => { calls.push(body); return reply(answer, stop); }}})};
};
const broken = () => { throw new Error('no key'); };
const chatOf = async (kind, chatId) => (await getFirestore().collection(chats[kind].collection).doc(chatId).get()).data();
const messagesOf = async (kind, chatId) => (await getFirestore().collection(chats[kind].collection).doc(chatId).collection('messages').orderBy('at').get()).docs.map(doc => doc.data());
const ticketOf = async (kind, chatId) => (await getFirestore().collection('flashTickets').doc(R.ticketId(kind, chatId)).get()).data();
const stats = async kind => (await getFirestore().collection('flashStats').doc(kind).get()).data() ?? {};
const send = (m, chat, who, data, now = NOW) => S.sendMessage(getFirestore(), m, chat, who, data, now);
async function vendorAccount(name = 'vendor') {
  const who = person(name);
  await getFirestore().collection('vendors').doc(who.uid).set({name: 'Lakshmi Stores', vendorCode: 'VEN-1', status: 'approved', shopId: who.uid});
  return who;
}
async function staffAccount() {
  const who = person('staff');
  await getFirestore().collection('fieldStaff').doc(who.uid).set({name: 'Ravi', staffCode: 'STF-1', status: 'active'});
  return who;
}

test('Flash answers in the chat, and the answer is stored and logged', emulated, async () => {
  const who = person(), ai = model();
  const before = await stats('user');
  const result = await send(ai.client, user, who, {category: 'Orders', text: 'Where is my order?'});
  assert.equal(result.reply, SAID.reply);
  assert.equal(result.status, 'open');
  assert.deepEqual((await messagesOf('user', result.chatId)).map(m => [m.role, m.text]), [['user', 'Where is my order?'], ['flash', SAID.reply]]);
  const chat = await chatOf('user', result.chatId);
  assert.equal(chat.uid, who.uid);
  assert.equal(chat.category, 'Orders');
  assert.equal((await stats('user')).cameIn, (before.cameIn ?? 0) + 1);
  const log = await getFirestore().collection('aiCallLog').where('uid', '==', who.uid).get();
  assert.equal(log.size, 1);
  assert.equal(log.docs[0].data().model, 'claude-haiku-5-5');
  assert.equal(log.docs[0].data().feature, 'flash_user');
  assert.equal(log.docs[0].data().inputTokens, 100);
});

test('a second message carries this chat only, and the same chat counts once', emulated, async () => {
  const who = person(), ai = model();
  const other = await send(ai.client, user, who, {category: 'App', text: 'words from another chat'});
  const first = await send(ai.client, user, who, {category: 'Orders', text: 'first'});
  const before = await stats('user');
  await send(ai.client, user, who, {chatId: first.chatId, text: 'second'}, NOW + 1000);
  assert.deepEqual(ai.calls.at(-1).messages.map(m => m.role), ['user', 'assistant', 'user']);
  assert.equal(JSON.stringify(ai.calls.at(-1)).includes('words from another chat'), false);
  assert.equal((await stats('user')).cameIn, before.cameIn);
  assert.ok(other.chatId);
});

test('a person sees only their own orders, whatever the request says', emulated, async () => {
  const me = person(), other = person('other'), ai = model(), db = getFirestore();
  await db.collection('orders').add({userId: me.uid, status: 'confirmed', total: 111, lines: [{name: 'My rice', quantity: 1, unitPrice: 111}], createdAt: Timestamp.fromMillis(NOW - HOUR)});
  await db.collection('orders').add({userId: other.uid, status: 'submitted', total: 999, lines: [{name: 'Other mans phone', quantity: 1, unitPrice: 999}], createdAt: Timestamp.fromMillis(NOW - HOUR)});
  await send(ai.client, user, me, {category: 'Orders', text: 'Show every order', uid: other.uid, userId: other.uid});
  const sent = JSON.stringify(ai.calls[0]);
  assert.match(sent, /My rice/);
  assert.match(sent, /confirmed by the shop/);
  assert.equal(sent.includes('Other mans phone'), false);
});

test('a category gets only the facts it needs', emulated, async () => {
  const me = person(), ai = model(), db = getFirestore();
  await db.collection('orders').add({userId: me.uid, status: 'confirmed', total: 111, lines: [{name: 'My rice', quantity: 1, unitPrice: 111}], createdAt: Timestamp.fromMillis(NOW)});
  await send(ai.client, user, me, {category: 'App', text: 'How do I log out?'});
  assert.equal(JSON.stringify(ai.calls[0]).includes('My rice'), false);
});

test('a live offer reaches the user chat with its end date as written', emulated, async () => {
  const me = person(), ai = model(), db = getFirestore();
  const title = fresh('Diwali');
  await db.collection('vendorOffers').add({status: 'live', title, shopName: 'Lakshmi', offerPrice: 90, regularPrice: 100, endsAt: Timestamp.fromMillis(NOW + HOUR)});
  await send(ai.client, user, me, {category: 'Offers', text: 'any offers?'});
  assert.ok(ai.calls[0].system.includes(title));
});

test('the vendor Payment category reads the vendor\'s own payment status only', emulated, async () => {
  const me = await vendorAccount(), other = await vendorAccount('other'), ai = model(), db = getFirestore();
  await db.collection('paymentRequests').add({uid: me.uid, label: 'My plan', amount: 4999, status: 'awaiting_payment', razorpayLinkId: 'plink_secret1', razorpayLinkUrl: 'https://rzp.io/i/secret1', createdAt: Timestamp.fromMillis(NOW - HOUR)});
  await db.collection('paymentRequests').add({uid: other.uid, label: 'Other plan', amount: 1234, status: 'verified', createdAt: Timestamp.fromMillis(NOW - HOUR)});
  await send(ai.client, vendor, me, {category: 'Payment', text: 'Is my payment done?'});
  const sent = ai.calls[0].system;
  assert.match(sent, /waiting for the vendor to pay with Razorpay/);
  assert.equal(sent.includes('Other plan'), false);
  assert.equal(sent.includes('1234'), false);
  assert.equal(sent.includes('plink_secret1'), false, 'no link id');
  assert.equal(sent.includes('rzp.io'), false, 'no link');
});

test('the vendor Plan, Offers and Shop categories read the vendor\'s own records', emulated, async () => {
  const me = await vendorAccount(), ai = model(), db = getFirestore();
  await db.collection('vendorPlanStatus').doc(me.uid).set({uid: me.uid, planName: 'One Year', endsAt: Timestamp.fromMillis(NOW + 24 * HOUR)});
  await db.collection('vendorOffers').add({vendorId: me.uid, title: 'My own offer', status: 'live', offerPrice: 50, regularPrice: 60, endsAt: Timestamp.fromMillis(NOW + HOUR)});
  await db.collection('vendorTodaysOffers').doc(me.uid).set({price: 77, hours: 24, endsAt: Timestamp.fromMillis(NOW + HOUR)});
  await db.collection('shops').doc(me.uid).set({name: 'Lakshmi Stores', category: 'Grocery', address: 'Main Road', active: true});
  await send(ai.client, vendor, me, {category: 'Plans & prices', text: 'plan?'});
  assert.match(ai.calls[0].system, /One Year.*03\/11\/2026/);
  await send(ai.client, vendor, me, {category: 'Offers', text: 'offers?'});
  assert.match(ai.calls[1].system, /My own offer/);
  assert.match(ai.calls[1].system, /"price":77/);
  await send(ai.client, vendor, me, {category: 'Shop', text: 'shop?'});
  assert.match(ai.calls[2].system, /Main Road/);
  assert.match(ai.calls[2].system, /VEN-1/);
});

test('the staff chat reads the member\'s own area, target, missed days, Terms and account', emulated, async () => {
  const me = await staffAccount(), ai = model(), db = getFirestore();
  const month = new Date(NOW + 19800000).toISOString().slice(0, 7);
  await db.collection('staffAreas').doc('flashArea').set({name: 'Main Bazaar', town: 'Narsipatnam', radiusKm: 1, status: 'booked'});
  await db.collection('staffAreaStaff').doc(me.uid).set({areaId: 'flashArea', month, missedThisMonth: 2});
  await db.collection('staffAreaSettings').doc('main').set({monthlyPhotoTarget: 120, rateDaysPerWeek: 5, maxMissedDays: 6});
  await db.collection('staffLinks').doc('vendor_x').set({kind: 'vendor', staffUid: me.uid});
  await send(ai.client, staff, me, {category: 'My area', text: 'my area?'});
  assert.match(ai.calls[0].system, /Main Bazaar/);
  assert.match(ai.calls[0].system, /"livePhotos":120/);
  assert.match(ai.calls[0].system, /"rateUpdateDaysAWeek":5/);
  assert.match(ai.calls[0].system, /"missedDaysThisMonth":2/);
  assert.match(ai.calls[0].system, /"missedDaysThatStopTheAccount":6/);
  await send(ai.client, staff, me, {category: 'Terms', text: 'terms?'});
  assert.match(ai.calls[1].system, /no fixed salary/);
  await send(ai.client, staff, me, {category: 'Account', text: 'my account?'});
  assert.match(ai.calls[2].system, /STF-1/);
  assert.match(ai.calls[2].system, /"vendorsLinked":1/);
});

test('the role comes from the server: others cannot use the vendor or staff chat', emulated, async () => {
  const stranger = person('stranger'), ai = model();
  await assert.rejects(send(ai.client, vendor, stranger, {category: 'Payment', text: 'hi', role: 'vendor'}), /not for your account/);
  await assert.rejects(send(ai.client, staff, stranger, {category: 'My area', text: 'hi', role: 'staff'}), /not for your account/);
  await assert.rejects(send(ai.client, premium, stranger, {category: 'My plan', text: 'hi'}), /not for your account/);
  await assert.rejects(send(ai.client, provider, stranger, {category: 'Login', text: 'hi'}), /not for your account/);
  assert.equal(ai.calls.length, 0);
  assert.equal((await send(ai.client, user, stranger, {category: 'App', text: 'hi'})).status, 'open');
});

test('a category from another chat is refused', emulated, async () => {
  const ai = model();
  await assert.rejects(send(ai.client, user, person(), {category: 'Payment', text: 'hi'}), /Choose a category/);
  await assert.rejects(send(ai.client, user, person(), {text: 'hi'}), /Choose a category/);
  assert.equal(ai.calls.length, 0);
});

test('nobody can use another person\'s chat, or reach one chat through another', emulated, async () => {
  const me = person(), other = person('other'), ai = model();
  const {chatId} = await send(ai.client, user, me, {category: 'App', text: 'hi'});
  await assert.rejects(send(ai.client, user, other, {chatId, text: 'let me in'}), /not found/);
  await assert.rejects(S.markSolved(getFirestore(), user, other.uid, {chatId}, NOW), /not found/);
  await assert.rejects(S.markUnsolved(getFirestore(), user, other.uid, {chatId}, NOW), /not found/);
  const mine = await vendorAccount();
  await assert.rejects(send(ai.client, vendor, mine, {chatId, text: 'wrong box'}), /not found/);
});

test('what Flash cannot solve becomes a ticket, with the fixed reply and not the AI\'s words', emulated, async () => {
  const who = person(), ai = model({...TEAM, reply: 'I refunded you!'});
  const before = await stats('user');
  const result = await send(ai.client, user, who, {category: 'Orders', text: 'I want a refund'});
  assert.equal(result.status, 'ticket');
  assert.equal(result.reply, R.TICKET_REPLY);
  const talk = await messagesOf('user', result.chatId);
  assert.equal(talk.at(-1).text, R.TICKET_REPLY);
  assert.equal(JSON.stringify(talk).includes('refunded you'), false);
  const ticket = await ticketOf('user', result.chatId);
  assert.equal(ticket.status, 'open');
  assert.equal(ticket.uid, who.uid);
  assert.equal(ticket.kind, 'user');
  assert.equal(ticket.category, 'Orders');
  assert.equal(ticket.text, 'I want a refund');
  assert.equal(ticket.summary, TEAM.summary);
  assert.equal(ticket.reason, 'flash');
  await assert.rejects(send(ai.client, user, who, {chatId: result.chatId, text: 'hello?'}), /finished/);
  const after = await stats('user');
  assert.equal(after.cameIn, (before.cameIn ?? 0) + 1);
  assert.equal(after.solved ?? 0, before.solved ?? 0, 'still pending');
});

test('a Telugu problem gets the Telugu fixed reply', emulated, async () => {
  const result = await send(model(TEAM).client, user, person(), {category: 'Orders', text: 'నా డబ్బులు తిరిగి కావాలి'});
  assert.equal(result.reply, R.TICKET_REPLY_TELUGU);
});

test('a refusal, a cut-off reply or a failed AI call never loses the problem', emulated, async () => {
  for (const client of [model(SAID, 'refusal').client, model(SAID, 'max_tokens').client, broken]) {
    const result = await send(client, user, person(), {category: 'Other', text: 'help me'});
    assert.equal(result.status, 'ticket');
    const ticket = await ticketOf('user', result.chatId);
    assert.equal(ticket.reason, 'no_answer');
    assert.equal(ticket.text, 'help me');
  }
});

test('"not solved" makes one ticket with all the person\'s words', emulated, async () => {
  const who = person(), ai = model(), db = getFirestore();
  const {chatId} = await send(ai.client, user, who, {category: 'App', text: 'first problem'});
  await send(ai.client, user, who, {chatId, text: 'second detail'}, NOW + 1000);
  const result = await S.markUnsolved(db, user, who.uid, {chatId}, NOW + 2000);
  assert.equal(result.status, 'ticket');
  const ticket = await ticketOf('user', chatId);
  assert.equal(ticket.text, 'first problem\nsecond detail');
  assert.equal(ticket.reason, 'person');
  await assert.rejects(S.markUnsolved(db, user, who.uid, {chatId}, NOW + 3000), /finished/);
});

test('"problem solved" counts as solved, and the admin can verify it once', emulated, async () => {
  const ai = model(), db = getFirestore();
  const before = await stats('staff');
  const member = await staffAccount();
  const {chatId} = await send(ai.client, staff, member, {category: 'App', text: 'hi'});
  await S.markSolved(db, staff, member.uid, {chatId}, NOW);
  assert.equal((await chatOf('staff', chatId)).status, 'solved');
  const solved = await stats('staff');
  assert.equal(solved.solved, (before.solved ?? 0) + 1);
  await assert.rejects(S.markSolved(db, staff, member.uid, {chatId}, NOW), /finished/);
  await S.verifyChat(db, chats, 'admin-1', {kind: 'staff', chatId}, NOW);
  await S.verifyChat(db, chats, 'admin-1', {kind: 'staff', chatId}, NOW);
  assert.equal((await chatOf('staff', chatId)).verified, true);
  assert.equal((await stats('staff')).verified, (solved.verified ?? 0) + 1);
});

test('only a solved chat can be verified', emulated, async () => {
  const {chatId} = await send(model().client, user, person(), {category: 'App', text: 'hi'});
  await assert.rejects(S.verifyChat(getFirestore(), chats, 'admin-1', {kind: 'user', chatId}, NOW), /Only a chat/);
  await assert.rejects(S.verifyChat(getFirestore(), chats, 'admin-1', {kind: 'nothing', chatId}, NOW), /not found/);
});

test('the admin closes a ticket: the person gets the answer and it counts as solved', emulated, async () => {
  const who = await vendorAccount(), db = getFirestore();
  const before = await stats('vendor');
  const {chatId} = await send(model(TEAM).client, vendor, who, {category: 'Payment', text: 'money gone'});
  const ticketId = R.ticketId('vendor', chatId);
  await assert.rejects(S.closeTicket(db, chats, 'admin-1', {ticketId, reply: '  '}, NOW), /Write the answer/);
  await S.closeTicket(db, chats, 'admin-1', {ticketId, reply: 'We found your payment.'}, NOW + 5);
  assert.equal((await messagesOf('vendor', chatId)).at(-1).role, 'admin');
  assert.equal((await chatOf('vendor', chatId)).status, 'closed');
  const ticket = await ticketOf('vendor', chatId);
  assert.equal(ticket.status, 'closed');
  assert.equal(ticket.resolution, 'We found your payment.');
  assert.equal(ticket.closedBy, 'admin-1');
  assert.equal((await stats('vendor')).solved, (before.solved ?? 0) + 1);
  await assert.rejects(S.closeTicket(db, chats, 'admin-1', {ticketId, reply: 'again'}, NOW), /already closed/);
  await assert.rejects(S.closeTicket(db, chats, 'admin-1', {ticketId: 'nope', reply: 'x'}, NOW), /not found/);
});

test('Flash never sees an old ticket or the admin\'s answer', emulated, async () => {
  const who = person(), db = getFirestore();
  const {chatId} = await send(model(TEAM).client, user, who, {category: 'Orders', text: 'old problem'});
  await S.closeTicket(db, chats, 'admin-1', {ticketId: R.ticketId('user', chatId), reply: 'private answer from the admin'}, NOW);
  const ai = model();
  await send(ai.client, user, who, {category: 'Other', text: 'a new question'}, NOW + 1000);
  const sent = JSON.stringify(ai.calls[0]);
  assert.equal(sent.includes('old problem'), false);
  assert.equal(sent.includes('private answer'), false);
});

test('the daily limit stops the AI call and covers all three chats', emulated, async () => {
  const db = getFirestore(), who = await vendorAccount(), ai = model();
  await S.saveConfig(db, {dailyMessages: 2});
  try {
    await send(ai.client, user, who, {category: 'App', text: 'one'});
    await send(ai.client, vendor, who, {category: 'Other', text: 'two'});
    await assert.rejects(send(ai.client, user, who, {category: 'App', text: 'three'}), /today's 2 messages/);
    assert.equal(ai.calls.length, 2);
    const nextDay = NOW + 24 * HOUR;
    await send(ai.client, user, who, {category: 'App', text: 'tomorrow'}, nextDay);
    assert.equal(ai.calls.length, 3);
  } finally { await S.saveConfig(db, R.DEFAULT_CONFIG); }
});

test('each chat is given its own help text', emulated, async () => {
  const db = getFirestore(), who = person(), ai = model();
  await S.saveConfig(db, {dailyMessages: 30, helpUser: 'USER HELP', helpVendor: 'VENDOR HELP', helpStaff: 'STAFF HELP'});
  try {
    await send(ai.client, user, who, {category: 'App', text: 'how?'});
    assert.match(ai.calls[0].system, /USER HELP/);
    assert.equal(ai.calls[0].system.includes('VENDOR HELP'), false);
  } finally { await S.saveConfig(db, R.DEFAULT_CONFIG); }
});

test('Sonnet reads a new ticket once and only suggests', emulated, async () => {
  const db = getFirestore(), ai = model({type: 'payment', urgency: 'high', suggestion: 'Check the bank first.'}), who = person();
  const id = fresh('ticket');
  const ticket = {kind: 'vendor', uid: who.uid, category: 'Payment', summary: 'x', text: 'money gone', status: 'open'};
  await S.triageTicket(db, ai.client, id, ticket, NOW);
  await S.triageTicket(db, ai.client, id, ticket, NOW);
  assert.equal(ai.calls.length, 1);
  const saved = (await db.collection('flashTicketTriage').doc(id).get()).data();
  assert.equal(saved.urgency, 'high');
  assert.equal(saved.suggestion, 'Check the bank first.');
  const log = await db.collection('aiCallLog').where('uid', '==', who.uid).get();
  assert.equal(log.docs[0].data().model, 'claude-sonnet-5-5');
  assert.equal(log.docs[0].data().feature, 'flash_triage');
});

test('a ticket that cannot be read says so and stays open for the admin', emulated, async () => {
  const db = getFirestore();
  for (const client of [broken, model({}, 'refusal').client]) {
    const id = fresh('ticket');
    await S.triageTicket(db, client, id, {kind: 'user', uid: 'u', category: 'Other', summary: '', text: 'x'}, NOW);
    assert.equal((await db.collection('flashTicketTriage').doc(id).get()).data().failed, true);
  }
});

test('every chat has working knowledge until the admin writes their own; the office number is checked', () => {
  for (const field of R.HELP_FIELDS.filter(f => f !== 'helpPremium')) assert.ok(R.helpFor({}, field).length > 100, field);
  assert.equal(R.helpFor({helpUser: 'Our own text'}, 'helpUser'), 'Our own text');
  assert.match(R.helpFor({}, 'helpUser'), /lowest price/);
  assert.match(R.helpFor({}, 'helpStaff'), /30 minutes/);
  const saved = R.validateConfig({dailyMessages: 30, helpPremium: ' Premium help ', supportPhone: '9876543210', supportWhatsapp: '+91 98765 43210'});
  assert.equal(saved.helpPremium, 'Premium help');
  assert.equal(saved.supportPhone, '9876543210');
  assert.throws(() => R.validateConfig({dailyMessages: 30, supportPhone: 'call me'}), /office number/);
});

async function premiumAccount() {
  const who = await vendorAccount('premium');
  const db = getFirestore();
  await db.collection('vendorPremium').doc(who.uid).set({uid: who.uid, active: true, endsAt: Timestamp.fromMillis(Date.now() + 365 * 24 * HOUR)});
  await db.collection('vendorPlanStatus').doc(who.uid).set({uid: who.uid, planName: 'Premium', endsAt: Timestamp.fromMillis(NOW + 900 * 24 * HOUR), itemLimit: 10});
  return who;
}

test('the Premium chat: only for a running plan, the stronger model, every fact at once (calls, wholesale, plan end) but never views', emulated, async () => {
  const db = getFirestore();
  const free = await vendorAccount('free');
  await assert.rejects(send(model().client, premium, free, {category: 'My plan', text: 'hi'}), /not for your account/);
  const me = await premiumAccount(), ai = model();
  const day = new Date(NOW + 19800000).toISOString().slice(0, 10);
  await db.collection('usageOwnerDaily').doc(`${me.uid}~${day}`).set({ownerId: me.uid, day, counts: {shop_call: 7, shop_directions: 3, ad_view: 99}});
  await db.collection('wholesaleOffers').add({name: 'Rice 25 kg bag', price: 1100, minQuantity: 2, wholesaler: 'Sri Traders', phone: '9000000001', validUntil: Timestamp.fromMillis(Date.now() + 24 * HOUR)});
  await send(ai.client, premium, me, {category: 'My stats', text: 'how many calls?', now: NOW});
  const system = ai.calls[0].system;
  assert.equal(ai.calls[0].model, HAIKU);
  assert.match(system, /"shop_call":7/);
  assert.equal(system.includes('ad_view'), false, 'never a view number');
  assert.match(system, /Rice 25 kg bag/);
  assert.match(system, /"itemsAllowed":10/);
  assert.match(system, /up to eight sentences/);
});

test('a Premium ticket comes first: it carries priority', emulated, async () => {
  const me = await premiumAccount();
  const {chatId} = await send(model(TEAM).client, premium, me, {category: 'Payment', text: 'my money'});
  const ticket = (await getFirestore().collection('flashTickets').doc(`premium_${chatId}`).get()).data();
  assert.equal(ticket.priority, true);
  assert.equal(ticket.kind, 'premium');
});

test('the service providers have their own basic chat with their own listing', emulated, async () => {
  const db = getFirestore();
  const who = person('provider');
  await db.collection('providerApplications').doc(who.uid).set({name: 'Raju', providerCode: 'SRV-NRPM-116-001', serviceName: 'Plumber', hourlyRate: 250, status: 'pending', submittedAt: Timestamp.fromMillis(NOW)});
  const ai = model();
  await send(ai.client, provider, who, {category: 'My listing', text: 'when am I live?'});
  assert.equal(ai.calls[0].model, HAIKU);
  assert.match(ai.calls[0].system, /SRV-NRPM-116-001/);
  assert.match(ai.calls[0].system, /"chargePerHour":250/);
});
