import '../flash_data.dart';

/// The free vendors' chat box (basic). Premium vendors have the advanced one (premium/premium_chat.dart).
const vendorFlashChat = FlashChatSetup(
  kind: 'vendor',
  // The chat's name in every app (owner, 13 Nov 2026).
  title: 'Support Team',
  adminTitle: 'Vendors',
  collection: 'flashVendorChats',
  callable: 'flashVendorChat',
  route: '/flash-vendor-chat',
  categories: ['Login', 'Plans & prices', 'Items & photos', 'Offers', 'Payment', 'Shop', 'Other'],
);
