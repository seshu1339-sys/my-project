import '../flash_data.dart';

/// The customers' chat box (service providers have their own, provider/provider_chat.dart).
const userFlashChat = FlashChatSetup(
  kind: 'user',
  title: 'Flash Help',
  adminTitle: 'Users',
  collection: 'flashUserChats',
  callable: 'flashUserChat',
  route: '/flash-user-chat',
  categories: ['Search & shops', 'Offers', 'Services', 'App', 'Orders', 'Other'],
);
