'use strict';
// The Claude models of every AI feature, in one place (owner, 13 Nov 2026). One Anthropic key (the ANTHROPIC_API_KEY secret) for all.
//   chat         Flash chat in the customer, vendor and staff apps (all five chats)      Claude Haiku 5.5
//   photoSearch  photo search: the product in a customer's photo becomes search words     Claude Haiku 5.5
//   admin        the admin panel's AI assistant (reports, counts, the admin's questions)  Claude Sonnet 5.5
//               and the Support Inbox's ticket reading (Flash triage)
const HAIKU = 'claude-haiku-5-5';
const SONNET = 'claude-sonnet-5-5';
const AI_MODELS = Object.freeze({chat: HAIKU, photoSearch: HAIKU, admin: SONNET});

/// True when the key is a real one (the secret holds a placeholder such as "XX" until the owner sets the key): without it no AI feature
/// calls Anthropic at all.
const keyIsSet = key => typeof key === 'string' && key.trim().length >= 20 && !/^x+$/i.test(key.trim());

module.exports = {AI_MODELS, HAIKU, SONNET, keyIsSet};
