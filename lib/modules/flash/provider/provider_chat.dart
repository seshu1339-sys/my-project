import '../flash_data.dart';

/// The service providers' chat box (the same basic level as free vendors).
const providerFlashChat = FlashChatSetup(
  kind: 'provider',
  title: 'Flash Services Help',
  adminTitle: 'Services',
  collection: 'flashProviderChats',
  callable: 'flashProviderChat',
  route: '/flash-provider-chat',
  categories: ['Login', 'My listing', 'Charge per hour', 'App', 'Other'],
);
