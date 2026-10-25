import 'catalog.dart';
import 'shop_ads.dart';

// The admin's staff report (staff spec point 7): for every field-staff member, their Staff ID and phone and how many vendors and
// service providers they added (staffAdditions, functions/staff-additions.js), with each one's ID (VEN-... / SRV-...) and phone.

class StaffReportRow {
  StaffReportRow(this.staffId, this.staff, this.additions);
  final String staffId;
  final Entry? staff;
  final List<Entry> additions;

  String get name => staff?.text('name', staffId) ?? (additions.isEmpty ? staffId : additions.first.text('staffName', staffId));
  String get code => staff?.text('staffCode') ?? (additions.isEmpty ? '' : additions.first.text('staffCode'));
  String get phone => staff?.text('phone') ?? '';
  int get total => additions.length;
  int get live => additions.where((a) => a.text('status') == 'approved').length;
  int get waiting => additions.where((a) => a.text('status') == 'pending').length;
  int get rejected => additions.where((a) => a.text('status') == 'rejected').length;
  int get autoApproved => additions.where((a) => a.data['autoApproved'] == true).length;
}

/// The person an addition is about (the vendor or the service provider).
Map<String, dynamic> staffAdditionPerson(Entry addition) =>
    Map<String, dynamic>.from((addition.text('kind') == 'provider' ? addition.data['provider'] : addition.data['vendor']) as Map? ?? const {});

/// The ID it got: the Vendor ID or the Provider ID.
String staffAdditionCode(Entry addition) => addition.text('kind') == 'provider' ? addition.text('providerCode') : addition.text('vendorCode');

/// Where it is: live (and whether it went live by itself), waiting for the admin, or not approved.
String staffAdditionState(Entry addition) => switch (addition.text('status')) {
  'approved' => addition.data['autoApproved'] == true ? 'Live (auto-approved)' : 'Live',
  'rejected' => 'Not approved',
  _ => 'Waiting',
};

/// One row per staff member (every staff record, and anyone who added something without one), the ones who added the most first;
/// each row's additions newest first.
List<StaffReportRow> staffReport(List<Entry> staff, List<Entry> additions) {
  final byStaff = <String, List<Entry>>{};
  for (final a in additions) {
    byStaff.putIfAbsent(a.text('staffUid'), () => []).add(a);
  }
  DateTime when(Entry a) => shopAdTime(a.data['submittedAt']) ?? DateTime(2000);
  final rows = [
    for (final s in staff) StaffReportRow(s.id, s, (byStaff.remove(s.id) ?? [])..sort((a, b) => when(b).compareTo(when(a)))),
    for (final e in byStaff.entries) StaffReportRow(e.key, null, e.value..sort((a, b) => when(b).compareTo(when(a)))),
  ];
  rows.sort((a, b) => a.total != b.total ? b.total.compareTo(a.total) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return rows;
}

/// Whether a row matches the admin's search: the staff member's name, Staff ID or phone, or the name, ID or phone of anyone they added.
bool staffReportMatches(StaffReportRow row, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  bool has(Object? v) => '${v ?? ''}'.toLowerCase().contains(q);
  if (has(row.name) || has(row.code) || has(row.phone)) return true;
  return row.additions.any((a) {
    final person = staffAdditionPerson(a);
    return has(person['name']) || has(person['phone']) || has(staffAdditionCode(a));
  });
}
