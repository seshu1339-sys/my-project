import '../flash_data.dart';

/// The staff chat box.
const staffFlashChat = FlashChatSetup(
  kind: 'staff',
  // The chat's name in every app (owner, 13 Nov 2026).
  title: 'Support Team',
  adminTitle: 'Staff',
  collection: 'flashStaffChats',
  callable: 'flashStaffChat',
  route: '/flash-staff-chat',
  categories: ['My area', 'Targets', 'Missed days', 'Adding offers', 'Terms', 'Account', 'App', 'Other'],
);
