import '../flash_data.dart';

/// The service providers' chat box (the same basic level as free vendors).
const providerFlashChat = FlashChatSetup(
  kind: 'provider',
  // The chat's name in every app (owner, 13 Nov 2026).
  title: 'Support Team',
  adminTitle: 'Services',
  collection: 'flashProviderChats',
  callable: 'flashProviderChat',
  route: '/flash-provider-chat',
  categories: ['Login', 'My listing', 'Charge per hour', 'App', 'Other'],
);
