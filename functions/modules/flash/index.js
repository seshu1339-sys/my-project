'use strict';
const {requireRole, isAdminToken, loginEmail} = require('../../role-auth');
// Flash AI chat and tickets module. Five separate chats (customers, free vendors, Premium vendors, service providers, staff), each with its own endpoint, categories, rules and collection (user/, vendor/,
// staff/). Flash answers first; what it cannot solve becomes a ticket for the admin. Requires no other module; it reads only the documents
// of the person who is signed in.
//
//   flashUserChat | flashVendorChat | flashPremiumChat | flashProviderChat | flashStaffChat   signed in -> {action: send | solved | unsolved, chatId?, category?, text?}
//   closeFlashTicket                                   admin     -> answers the person and closes the ticket
//   verifyFlashChat                                    admin     -> marks a chat Flash solved as checked
//   saveFlashConfig                                    admin     -> daily limit and what Flash knows about each app
//   triageFlashTicket                                  trigger   -> Sonnet reads one new ticket and suggests; it changes nothing
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {getFirestore} = require('firebase-admin/firestore');
const {requireAdminSession} = require('../../admin-session');
const {anthropic, anthropicKey} = require('../ai-core');
const {saveConfig, sendMessage, markSolved, markUnsolved, closeTicket, verifyChat, triageTicket} = require('./store');

const chats = {user: require('./user/chat'), vendor: require('./vendor/chat'), premium: require('./premium/chat'), provider: require('./provider/chat'), staff: require('./staff/chat')};
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const fail = error => { throw new HttpsError('failed-precondition', error.message); };
function requireVerified(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  return request.auth.uid;
}
async function requireAdmin(request) {
  const uid = requireVerified(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
  return uid;
}

/// One chat's endpoint, for the role logins listed in [roles]. Who is asking comes only from the sign-in.
const chatEndpoint = (chat, roles) => onCall({...options, secrets: [anthropicKey], timeoutSeconds: 60}, async request => {
  const uid = requireRole(request, roles);
  const data = request.data || {};
  const db = getFirestore();
  try {
    if (data.action === 'solved') return await markSolved(db, chat, uid, data);
    if (data.action === 'unsolved') return await markUnsolved(db, chat, uid, data);
    return await sendMessage(db, anthropic, chat, {uid, email: loginEmail(request) ?? ''}, data);
  } catch (error) { return fail(error); }
});

// The general help chat: customers, and any vendor-app or staff-app login that has not registered yet (each login has its own chats).
exports.flashUserChat = chatEndpoint(chats.user, ['user', 'vendor', 'provider', 'staff']);
exports.flashVendorChat = chatEndpoint(chats.vendor, ['vendor']);
exports.flashStaffChat = chatEndpoint(chats.staff, ['staff']);
exports.flashPremiumChat = chatEndpoint(chats.premium, ['vendor']);
exports.flashProviderChat = chatEndpoint(chats.provider, ['provider']);
exports.closeFlashTicket = onCall(options, async request => {
  const uid = await requireAdmin(request);
  try { return await closeTicket(getFirestore(), chats, uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.verifyFlashChat = onCall(options, async request => {
  const uid = await requireAdmin(request);
  try { return await verifyChat(getFirestore(), chats, uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.saveFlashConfig = onCall(options, async request => {
  await requireAdmin(request);
  try { return await saveConfig(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.triageFlashTicket = onDocumentCreated({document: 'flashTickets/{ticketId}', region: 'asia-south1', maxInstances: 3, secrets: [anthropicKey], timeoutSeconds: 120}, async event => {
  await triageTicket(getFirestore(), anthropic, event.params.ticketId, event.data.data());
});
