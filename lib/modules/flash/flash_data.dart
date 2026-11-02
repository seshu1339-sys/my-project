import 'package:cloud_firestore/cloud_firestore.dart';

/// One of the three separate chats: its own box, categories, collection and server endpoint.
class FlashChatSetup {
  const FlashChatSetup({required this.kind, required this.title, required this.collection, required this.callable, required this.route, required this.categories, required this.adminTitle});
  final String kind, title, collection, callable, route, adminTitle;
  final List<String> categories;
}

class FlashMessage {
  const FlashMessage({required this.role, required this.text});

  factory FlashMessage.fromData(Map<String, dynamic> data) => FlashMessage(role: data['role']?.toString() ?? '', text: data['text']?.toString() ?? '');

  /// user, flash or admin.
  final String role;
  final String text;
}

/// One conversation. status: open, solved, ticket or closed.
class FlashChat {
  const FlashChat({required this.id, required this.category, required this.status, this.who = '', this.email = '', this.at});

  factory FlashChat.fromData(String id, Map<String, dynamic> data) => FlashChat(
    id: id,
    category: data['category']?.toString() ?? '',
    status: data['status']?.toString() ?? '',
    who: data['who']?.toString() ?? '',
    email: data['email']?.toString() ?? '',
    at: (data['updatedAt'] as Timestamp?)?.toDate(),
  );

  final String id, category, status, who, email;
  final DateTime? at;

  String get statusLabel => switch (status) {
    'open' => 'Open',
    'ticket' => 'With our team',
    _ => 'Finished',
  };
}

class FlashTicket {
  const FlashTicket({required this.id, required this.chatId, required this.category, required this.text, this.who = '', this.email = '', this.summary = '', this.reason = '', this.at});

  factory FlashTicket.fromData(String id, Map<String, dynamic> data) => FlashTicket(
    id: id,
    chatId: data['chatId']?.toString() ?? '',
    category: data['category']?.toString() ?? '',
    text: data['text']?.toString() ?? '',
    who: data['who']?.toString() ?? '',
    email: data['email']?.toString() ?? '',
    summary: data['summary']?.toString() ?? '',
    reason: data['reason']?.toString() ?? '',
    at: (data['createdAt'] as Timestamp?)?.toDate(),
  );

  final String id, chatId, category, text, who, email, summary, reason;
  final DateTime? at;

  String get reasonLabel => switch (reason) {
    'person' => 'The person said Flash did not solve it',
    'no_answer' => 'Flash could not answer',
    _ => 'Flash sent this to the team',
  };
}

/// Sonnet's reading of one ticket: only a suggestion for the admin.
class FlashTriage {
  const FlashTriage({this.type = '', this.urgency = '', this.suggestion = '', this.failed = false});

  factory FlashTriage.fromData(Map<String, dynamic> data) => FlashTriage(
    type: data['type']?.toString() ?? '',
    urgency: data['urgency']?.toString() ?? '',
    suggestion: data['suggestion']?.toString() ?? '',
    failed: data['failed'] == true,
  );

  final String type, urgency, suggestion;
  final bool failed;
}

class FlashCounts {
  const FlashCounts({this.cameIn = 0, this.solved = 0, this.verified = 0});

  factory FlashCounts.fromData(Map<String, dynamic>? data) => FlashCounts(
    cameIn: (data?['cameIn'] as num?)?.toInt() ?? 0,
    solved: (data?['solved'] as num?)?.toInt() ?? 0,
    verified: (data?['verified'] as num?)?.toInt() ?? 0,
  );

  final int cameIn, solved, verified;
  int get pending => cameIn - solved;
}

class FlashConfig {
  const FlashConfig({this.dailyMessages = 30, this.helpUser = '', this.helpVendor = '', this.helpStaff = ''});

  factory FlashConfig.fromData(Map<String, dynamic>? data) => FlashConfig(
    dailyMessages: (data?['dailyMessages'] as num?)?.toInt() ?? 30,
    helpUser: data?['helpUser']?.toString() ?? '',
    helpVendor: data?['helpVendor']?.toString() ?? '',
    helpStaff: data?['helpStaff']?.toString() ?? '',
  );

  final int dailyMessages;
  final String helpUser, helpVendor, helpStaff;
}

/// A time as the apps show it: 02/11/2026 14:05.
String flashTime(DateTime? at) {
  if (at == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(at.day)}/${two(at.month)}/${at.year} ${two(at.hour)}:${two(at.minute)}';
}
