import 'package:cloud_firestore/cloud_firestore.dart';

/// Staff Links module (functions/modules/staff-links): a vendor or service provider registers themselves; a staff member links them by
/// their ID within 30 minutes. A link gives the staff member a read-only view only.
const staffLinkWindow = Duration(minutes: 30);

/// One link (a `staffLinks` document).
class StaffLink {
  const StaffLink({
    required this.id,
    required this.kind,
    required this.accountUid,
    required this.code,
    required this.name,
    required this.staffUid,
    required this.staffCode,
    required this.staffName,
    this.town = '',
    this.linkedAt,
  });

  factory StaffLink.fromData(String id, Map<String, dynamic> data) {
    final linked = data['linkedAt'];
    return StaffLink(
      id: id,
      kind: data['kind']?.toString() ?? 'vendor',
      accountUid: data['accountUid']?.toString() ?? '',
      code: data['code']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      town: data['town']?.toString() ?? '',
      staffUid: data['staffUid']?.toString() ?? '',
      staffCode: data['staffCode']?.toString() ?? '',
      staffName: data['staffName']?.toString() ?? '',
      linkedAt: linked is Timestamp ? linked.toDate() : null,
    );
  }

  final String id, kind, accountUid, code, name, town, staffUid, staffCode, staffName;
  final DateTime? linkedAt;

  bool get provider => kind == 'provider';
}

/// The link id of a vendor or provider (the same as functions/modules/staff-links/rules.js linkId).
String staffLinkId(String kind, String accountUid) => '${kind}_$accountUid';

/// Whether [value] looks like a Vendor ID (VEN-NRPM-116-325) or a Provider ID (SRV-NRPM-116-001).
bool looksLikeAccountCode(String value) => RegExp(r'^(VEN|SRV)-[A-Z]{2,6}-\d{3}-\d{3}$').hasMatch(value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ''));

String linkDate(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

/// What a linked vendor has done, as the staff member reads it: how many items, how many updated today, and when the last update was.
class LinkedUpdates {
  const LinkedUpdates({required this.items, required this.updatedToday, this.lastUpdate});
  final int items, updatedToday;
  final DateTime? lastUpdate;
}

DateTime? _time(Object? v) => v is Timestamp ? v.toDate() : v is String ? DateTime.tryParse(v) : null;

bool _sameDay(DateTime a, DateTime b) {
  // India date, like the customer's "Updated today".
  final x = a.toUtc().add(const Duration(hours: 5, minutes: 30)), y = b.toUtc().add(const Duration(hours: 5, minutes: 30));
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// The updates of a vendor's items (their products: price set time or last change).
LinkedUpdates linkedUpdates(Iterable<Map<String, dynamic>> items, DateTime now) {
  DateTime? last;
  var today = 0;
  var count = 0;
  for (final item in items) {
    count++;
    final times = [_time(item['priceSetAt']), _time(item['updatedAt'])].whereType<DateTime>();
    if (times.isEmpty) continue;
    final latest = times.reduce((a, b) => a.isAfter(b) ? a : b);
    if (_sameDay(latest, now)) today++;
    if (last == null || latest.isAfter(last)) last = latest;
  }
  return LinkedUpdates(items: count, updatedToday: today, lastUpdate: last);
}
