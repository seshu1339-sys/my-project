import '../flash_data.dart';

/// The customers' chat box (service providers have their own, provider/provider_chat.dart).
const userFlashChat = FlashChatSetup(
  kind: 'user',
  // The chat's name in every app (owner, 13 Nov 2026).
  title: 'Support Team',
  adminTitle: 'Users',
  collection: 'flashUserChats',
  callable: 'flashUserChat',
  route: '/flash-user-chat',
  categories: ['Search & shops', 'Offers', 'Services', 'App', 'Orders', 'Other'],
);
