import '../flash_data.dart';

/// The Premium vendors' advanced chat box: smarter, more detailed answers from all their own records, priority with the team, and the
/// office's phone and WhatsApp on the page.
const premiumFlashChat = FlashChatSetup(
  kind: 'premium',
  // The chat's name in every app (owner, 13 Nov 2026).
  title: 'Support Team',
  adminTitle: 'Premium vendors',
  collection: 'flashPremiumChats',
  callable: 'flashPremiumChat',
  route: '/flash-premium-chat',
  categories: ['My plan', 'My stats', 'Ads & offers', 'Wholesale', 'Items & prices', 'Payment', 'Other'],
  officeContact: true,
);
