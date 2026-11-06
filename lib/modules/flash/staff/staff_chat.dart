import '../flash_data.dart';

/// The staff chat box.
const staffFlashChat = FlashChatSetup(
  kind: 'staff',
  title: 'Flash Staff Help',
  adminTitle: 'Staff',
  collection: 'flashStaffChats',
  callable: 'flashStaffChat',
  route: '/flash-staff-chat',
  categories: ['My area', 'Targets', 'Missed days', 'Adding offers', 'Terms', 'Account', 'App', 'Other'],
);
