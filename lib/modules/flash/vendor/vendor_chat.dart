import '../flash_data.dart';

/// The vendors' chat box.
const vendorFlashChat = FlashChatSetup(
  kind: 'vendor',
  title: 'Flash Vendor Help',
  adminTitle: 'Vendors',
  collection: 'flashVendorChats',
  callable: 'flashVendorChat',
  route: '/flash-vendor-chat',
  categories: ['Payment', 'Plan', 'Offers', 'Shop', 'Other'],
);
