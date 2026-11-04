import '../flash_data.dart';

/// The users' chat box. A service provider uses this one too.
const userFlashChat = FlashChatSetup(
  kind: 'user',
  title: 'Flash Help',
  adminTitle: 'Users',
  collection: 'flashUserChats',
  callable: 'flashUserChat',
  route: '/flash-user-chat',
  categories: ['Orders', 'Offers', 'App', 'Other'],
);
