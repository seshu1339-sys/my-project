import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/staff_report.dart';
import 'package:ecommerce_app/ui/admin_staff_report.dart';

const _staff = [
  Entry('kiran', {'name': 'Kiran Kumar', 'staffCode': 'STF-NRPM-116-482', 'phone': '9876543210', 'status': 'active', 'autoApprove': true}),
  Entry('ravi', {'name': 'Ravi Teja', 'staffCode': 'STF-TUNI-401-117', 'phone': '9876500011', 'status': 'active'}),
  Entry('anil', {'name': 'Anil', 'staffCode': 'STF00003', 'phone': '9000000003', 'status': 'suspended'}),
];
const _additions = [
  Entry('a1', {'kind': 'vendor', 'status': 'approved', 'staffUid': 'kiran', 'vendorCode': 'VEN-NRPM-116-321', 'vendor': {'name': 'Lakshmi Kirana', 'phone': '9876511111'}, 'submittedAt': '2026-10-20T09:00:00.000'}),
  Entry('a2', {'kind': 'provider', 'status': 'approved', 'autoApproved': true, 'staffUid': 'kiran', 'providerCode': 'SRV-NRPM-116-208', 'serviceName': 'Plumber', 'provider': {'name': 'Suresh Kumar', 'phone': '9876522222'}, 'submittedAt': '2026-10-24T09:00:00.000'}),
  Entry('a3', {'kind': 'vendor', 'status': 'pending', 'staffUid': 'kiran', 'vendorCode': 'VEN-NRPM-118-407', 'vendor': {'name': 'Ravi Fruits', 'phone': '9876533333'}, 'submittedAt': '2026-10-25T09:00:00.000'}),
  Entry('a4', {'kind': 'vendor', 'status': 'rejected', 'staffUid': 'ravi', 'vendorCode': 'VEN-TUNI-401-233', 'vendor': {'name': 'Anil Stores', 'phone': '9876544444'}, 'submittedAt': '2026-10-23T09:00:00.000'}),
];

void main() {
  test('one row per staff member with their counts, the ones who added most first, each one\'s additions newest first', () {
    final rows = staffReport(_staff, _additions);
    expect(rows.map((r) => r.name), ['Kiran Kumar', 'Ravi Teja', 'Anil']);
    final kiran = rows.first;
    expect([kiran.code, kiran.phone, kiran.total, kiran.live, kiran.waiting, kiran.rejected, kiran.autoApproved], ['STF-NRPM-116-482', '9876543210', 3, 2, 1, 0, 1]);
    expect(kiran.additions.map((a) => a.id), ['a3', 'a2', 'a1'], reason: 'newest first');
    expect(rows[2].total, 0, reason: 'staff who added nobody are listed too');
    expect(staffAdditionCode(_additions[1]), 'SRV-NRPM-116-208');
    expect(staffAdditionState(_additions[1]), 'Live (auto-approved)');
    expect(staffAdditionState(_additions[2]), 'Waiting');
    expect(staffAdditionState(_additions[3]), 'Not approved');
    // search by the staff member, or by someone they added
    expect([for (final r in rows) if (staffReportMatches(r, 'STF-TUNI')) r.name], ['Ravi Teja']);
    expect([for (final r in rows) if (staffReportMatches(r, '9876522222')) r.name], ['Kiran Kumar'], reason: 'the phone of a provider Kiran added');
    expect([for (final r in rows) if (staffReportMatches(r, 'VEN-TUNI-401-233')) r.name], ['Ravi Teja']);
    // additions by someone with no staff record still count
    expect(staffReport(const [], [_additions[0]]).single.total, 1);
  });

  testWidgets('the report: Staff ID, phone and counts per staff member; opening one lists each added person\'s ID and phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: StaffReportPage(store: Store(), staff: Stream.value(_staff), additions: Stream.value(_additions))));
    await tester.pump();
    await tester.pump();
    expect(find.text('3 staff • 4 added • 2 live • 1 waiting • 1 not approved'), findsOneWidget);
    expect(find.text('Staff ID: STF-NRPM-116-482 • Phone: 9876543210 • Auto-approve on'), findsOneWidget);
    expect(find.text('3 added'), findsOneWidget);
    expect(find.text('2 live • 1 waiting • 0 not approved'), findsOneWidget);
    expect(find.text('Staff ID: STF00003 • Phone: 9000000003 • Suspended'), findsOneWidget);
    await tester.tap(find.text('Kiran Kumar'));
    await tester.pumpAndSettle();
    expect(find.text('Suresh Kumar • Plumber'), findsOneWidget);
    expect(find.text('Provider ID: SRV-NRPM-116-208 • Phone: 9876522222 • 24 Oct 2026'), findsOneWidget);
    expect(find.text('Live (auto-approved)'), findsOneWidget);
    expect(find.text('Vendor ID: VEN-NRPM-116-321 • Phone: 9876511111 • 20 Oct 2026'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('staff-report-search')), 'Anil Stores');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('staff-report-ravi')), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-report-kiran')), findsNothing);
  });
}
