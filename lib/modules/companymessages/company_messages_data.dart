import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/towns.dart' as towns;

// Company messages (owner, 18 Nov 2026: cost cuts part 5): official "LOCAMARKET Team" messages to vendors. The same rules as
// functions/modules/company-messages/rules.js (towns, categories, topics); the server decides who may send and to whom.

/// The message types, as vendors read them.
const companyMessageTypes = {
  'solved': 'Problem solved',
  'offer': 'New offer',
  'payment': 'Payment / charges change',
  'account': 'Reset / account info',
  'general': 'General info',
};

String companyTownKey(String town) => towns.townKey(town);
String companyCategoryKey(String category) => category.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
String companySlug(String value) {
  final s = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'x' : (s.length > 60 ? s.substring(0, 60) : s);
}

/// The push topics a vendor's app joins (functions/modules/company-messages/rules.js topicsFor makes the same names).
List<String> companyTopicsFor({required String uid, String town = '', String category = ''}) => [
  'cm_vendors_all',
  if (companyTownKey(town).isNotEmpty) 'cm_vendors_t_${companySlug(companyTownKey(town))}',
  if (companyCategoryKey(category).isNotEmpty) 'cm_vendors_c_${companySlug(companyCategoryKey(category))}',
  if (uid.isNotEmpty) 'cm_vendor_${companySlug(uid)}',
];

/// One company message, as the vendor and the admin read it.
class CompanyMessage {
  const CompanyMessage({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.sentAt,
    this.hasPhoto = false,
    this.oldAmount,
    this.newAmount,
    this.startsOn = '',
    this.showUntil = '',
    this.edited = false,
    this.deleted = false,
    this.all = false,
    this.towns = const [],
    this.categories = const [],
    this.vendorCodes = const [],
    this.direct = false,
    this.sentByRole = '',
    this.sentByCode = '',
    this.meantFor = 0,
    this.readCount = 0,
    this.pushes = 0,
    this.versions = const [],
  });

  factory CompanyMessage.from(String id, Map<String, dynamic> d) {
    final target = d['target'] is Map ? Map<String, dynamic>.from(d['target'] as Map) : const <String, dynamic>{};
    List<String> strings(Object? v) => [for (final x in (v is List ? v : const [])) '$x'];
    final by = d['sentBy'] is Map ? Map<String, dynamic>.from(d['sentBy'] as Map) : const <String, dynamic>{};
    return CompanyMessage(
      id: id,
      type: companyMessageTypes.containsKey(d['type']) ? '${d['type']}' : 'general',
      title: '${d['title'] ?? ''}',
      body: '${d['body'] ?? ''}',
      sentAt: _time(d['sentAt']),
      hasPhoto: d['hasPhoto'] == true,
      oldAmount: (d['oldAmount'] as num?)?.toDouble(),
      newAmount: (d['newAmount'] as num?)?.toDouble(),
      startsOn: '${d['startsOn'] ?? ''}',
      showUntil: '${d['showUntil'] ?? ''}',
      edited: d['edited'] == true,
      deleted: d['deleted'] == true,
      all: (d['all'] ?? target['all']) == true,
      towns: strings(d['towns'] ?? target['towns']),
      categories: strings(d['categories'] ?? target['categories']),
      vendorCodes: strings(target['vendorCodes']),
      direct: d['public'] == false,
      sentByRole: '${by['role'] ?? ''}',
      sentByCode: '${by['code'] ?? ''}',
      meantFor: (d['meantFor'] as num?)?.toInt() ?? 0,
      readCount: (d['readCount'] as num?)?.toInt() ?? 0,
      pushes: (d['pushes'] as num?)?.toInt() ?? 0,
      versions: [for (final v in (d['versions'] is List ? d['versions'] as List : const [])) if (v is Map) Map<String, dynamic>.from(v)],
    );
  }

  final String id, type, title, body, startsOn, showUntil, sentByRole, sentByCode;
  final DateTime? sentAt;
  final bool hasPhoto, edited, deleted, all, direct;
  final double? oldAmount, newAmount;
  final List<String> towns, categories, vendorCodes;
  final int meantFor, readCount, pushes;
  final List<Map<String, dynamic>> versions;

  String get typeLabel => companyMessageTypes[type] ?? 'General info';

  /// Still shown: not deleted and not past its "show until" day (Indian time).
  bool showingOn(DateTime now) {
    if (deleted) return false;
    if (showUntil.isEmpty) return true;
    final today = now.toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String().substring(0, 10);
    return showUntil.compareTo(today) >= 0;
  }

  /// A message for everyone, a town and / or a category fits this vendor.
  bool fits({required String town, required String category}) {
    if (direct) return true; // read only by the people it was sent to (the database rules)
    if (all) return true;
    final t = companyTownKey(town), c = companyCategoryKey(category);
    final townOk = towns.isEmpty || towns.contains(t);
    final catOk = categories.isEmpty || categories.contains(c);
    return (towns.isNotEmpty || categories.isNotEmpty) && townOk && catOk;
  }

  /// Who it went to, for the admin's log.
  String get targetText {
    if (all) return 'All vendors';
    if (vendorCodes.isNotEmpty) return vendorCodes.join(', ');
    return [if (towns.isNotEmpty) 'Town: ${towns.join(', ')}', if (categories.isNotEmpty) 'Category: ${categories.join(', ')}'].join(' + ');
  }
}

DateTime? _time(Object? v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;

/// "₹1,250" style amounts (no paise when whole).
String rupees(double? v) {
  if (v == null) return '';
  final whole = v == v.roundToDouble();
  return '₹${whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';
}

/// 18/11/2026 14:05 in Indian time.
String companyTime(DateTime? at) {
  if (at == null) return '';
  final l = at.toUtc().add(const Duration(hours: 5, minutes: 30));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// 2026-11-20 -> 20/11/2026.
String companyDay(String ymd) => ymd.length == 10 ? '${ymd.substring(8)}/${ymd.substring(5, 7)}/${ymd.substring(0, 4)}' : ymd;

/// The messages one vendor sees, newest first: the everyone-list that fits them and the ones sent to them by ID.
List<CompanyMessage> vendorInbox({
  required List<CompanyMessage> everyone,
  required List<CompanyMessage> mine,
  required String town,
  required String category,
  required DateTime now,
}) {
  final byId = <String, CompanyMessage>{};
  for (final m in [...everyone.where((m) => m.fits(town: town, category: category)), ...mine]) {
    if (m.showingOn(now)) byId[m.id] = m;
  }
  return byId.values.toList()..sort((a, b) => (b.sentAt ?? DateTime(0)).compareTo(a.sentAt ?? DateTime(0)));
}
