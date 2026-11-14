import 'package:ecommerce_app/modules/staffareas/admin_hex_cells.dart';
import 'package:ecommerce_app/modules/staffareas/hex_cell.dart';
import 'package:ecommerce_app/modules/staffareas/staff_area_model.dart';
import 'package:ecommerce_app/modules/staffareas/staff_hex_cell_page.dart';
import 'package:ecommerce_app/modules/staffareas/staff_terms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Staff hexagon cells in the apps (owner, 13 Nov 2026): the staff member's map and registration box, the Terms, and the admin's cells.
const _me = LatLng(17.7110, 83.3010);
List<List<double>> _hex(double lat, double lng, [double r = 0.004]) => [
  [lat + r, lng],
  [lat + r / 2, lng + r],
  [lat - r / 2, lng + r],
  [lat - r, lng],
  [lat - r / 2, lng - r],
  [lat + r / 2, lng - r],
];

Map<String, dynamic> _answer({String status = 'free', bool hasArea = false, List<double> center = const [17.7110, 83.3010]}) => {
  'cellId': '88618926a5fffff',
  'code': 'HX1-0F4K03J',
  'sizeKm': 1,
  'center': center,
  'status': status,
  'homeMaxKm': 5,
  'hasArea': hasArea,
  'myAreaCode': hasArea ? 'HX1-0F4K03J' : '',
  'cells': [
    {'cellId': '88618926a5fffff', 'code': 'HX1-0F4K03J', 'sizeKm': 1, 'status': status, 'outline': _hex(17.7110, 83.3010)},
    {'cellId': '88618926a7fffff', 'code': 'HX1-0F4K03K', 'sizeKm': 1, 'status': 'taken', 'outline': _hex(17.7190, 83.3010)},
    {'cellId': '87618926affffff', 'code': 'HX2-1WJCAV', 'sizeKm': 2, 'status': 'free', 'outline': _hex(17.7030, 83.3150, 0.01)},
  ],
};

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<List<HexRegistration>> _pump(WidgetTester tester, Map<String, dynamic> answer) async {
  _size(tester);
  final sent = <HexRegistration>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: StaffHexCellView(nearby: HexNearby.fromData(answer), me: _me, onRegister: (r) async => sent.add(r))),
  ));
  await tester.pump();
  return sent;
}

void main() {
  test('the server\'s answer is read: the cell here, its size, centre, and the cells around with their outlines', () {
    final n = HexNearby.fromData(_answer());
    expect([n.code, n.sizeKm, n.free, n.cells.length, n.homeMaxKm], ['HX1-0F4K03J', 1, true, 3, 5.0]);
    expect(n.here?.outline.length, 6);
    expect(n.cells[1].free, isFalse);
    expect(homeDistanceKm(const LatLng(17.7110, 83.3010), const LatLng(17.7560, 83.3010)), closeTo(5.0, 0.1));
  });

  testWidgets('a free cell: the box holds the cell; address, home pin and Terms are needed; then it registers', (tester) async {
    final sent = await _pump(tester, _answer());
    expect(find.text('HX1-0F4K03J • 1 km • Free'), findsOneWidget);
    expect(find.byKey(const ValueKey('hex-credit')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hex-register')));
    await tester.pump();
    expect(find.text('Enter your home address.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('hex-home-address')), 'Door 12-3-4, Asilmetta, Visakhapatnam');
    await tester.tap(find.byKey(const ValueKey('hex-register')));
    await tester.pump();
    expect(find.text('Put the pin on your home on the map.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hex-home-pin')));
    await tester.pump();
    expect(find.text('Now tap your home on the map'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('hex-map'))) + const Offset(20, 10));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('hex-home-distance')), findsOneWidget);
    expect(find.textContaining('km from the cell\'s centre'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hex-register')));
    await tester.pump();
    expect(find.text('Tick "I accept the Terms & Conditions".'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hex-terms')));
    await tester.tap(find.byKey(const ValueKey('hex-register')));
    await tester.pumpAndSettle();
    expect(sent.single.address, 'Door 12-3-4, Asilmetta, Visakhapatnam');
    expect(const Distance().as(LengthUnit.Kilometer, sent.single.home, _me), lessThan(1));
  });

  testWidgets('a home more than 5 km from the cell\'s centre is refused before sending', (tester) async {
    final sent = await _pump(tester, _answer(center: const [17.80, 83.3010]));
    await tester.enterText(find.byKey(const ValueKey('hex-home-address')), 'Door 5-6, Madhurawada, Visakhapatnam');
    await tester.tap(find.byKey(const ValueKey('hex-home-pin')));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('hex-map'))));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('hex-terms')));
    await tester.tap(find.byKey(const ValueKey('hex-register')));
    await tester.pump();
    expect(find.textContaining('Staff must live within 5 km'), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('a taken cell cannot be registered; a staff member with a cell sees theirs', (tester) async {
    await _pump(tester, _answer(status: 'taken'));
    expect(find.text('HX1-0F4K03J • 1 km • Taken'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('hex-register'))).onPressed, isNull);
    await _pump(tester, _answer(status: 'mine', hasArea: true));
    expect(find.text('Your cell: HX1-0F4K03J'), findsOneWidget);
    expect(find.byKey(const ValueKey('hex-register-box')), findsNothing);
  });

  testWidgets('the Terms always carry the cell rules (5 km from the centre) and the WorldPop credit', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StaffTermsView(settings: StaffAreaSettings(terms: 'Custom terms by the admin')))));
    expect(find.text('Custom terms by the admin'), findsOneWidget);
    expect(find.textContaining('within 5 km of the centre of your cell'), findsOneWidget);
    expect(find.text(worldPopCredit), findsOneWidget);
    expect(defaultStaffTerms, contains('9. You must be local: your home must be within 5 km of the centre of your cell.'));
  });

  test('an area that is a hexagon cell keeps its code, size and outline', () {
    final flat = [for (final p in _hex(17.7110, 83.3010)) ...p];
    final area = StaffArea.fromData('88618926a5fffff', {'name': 'HX1-0F4K03J · Visakhapatnam', 'town': 'Visakhapatnam', 'latitude': 17.711, 'longitude': 83.301, 'radiusKm': 0.57, 'status': 'booked', 'hexCode': 'HX1-0F4K03J', 'hexSizeKm': 1, 'hexOutline': flat});
    expect([area.hex, area.hexCode, area.hexSizeKm, area.outline.length], [true, 'HX1-0F4K03J', 1, 6]);
    expect(StaffArea.fromData('old', {'latitude': 17.7, 'longitude': 83.3, 'radiusKm': 1, 'status': 'free'}).hex, isFalse);
  });

  testWidgets('admin cells: who holds each cell; one click links the waiting vendors; cancel a staff ID with a reason', (tester) async {
    _size(tester);
    final calls = <String>[];
    final flat = [for (final p in _hex(17.7110, 83.3010)) ...p];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminHexCellsView(
          cells: [
            StaffArea.fromData('cellA', {'name': 'HX1-0F4K03J · Visakhapatnam', 'town': 'Visakhapatnam', 'latitude': 17.711, 'longitude': 83.301, 'radiusKm': 0.57, 'status': 'booked', 'hexCode': 'HX1-0F4K03J', 'hexSizeKm': 1, 'hexOutline': flat}),
          ],
          holders: {'cellA': AreaHolder.fromData({'staffUid': 's9', 'staffCode': 'STF-NRPM-116-702', 'staffName': 'Ravi', 'staffPhone': '9876500002'})},
          office: const [OfficeLink(id: 'vendor_v1', name: 'Lakshmi Kirana', code: 'VEN-NRPM-116-801', previousStaffCode: 'STF-NRPM-116-701')],
          onFree: (cell) async => calls.add('free ${cell.id}'),
          onPreviewRelink: (uid) async {
            calls.add('preview $uid');
            return {'count': 1, 'names': ['Lakshmi Kirana']};
          },
          onRelink: (uid) async {
            calls.add('relink $uid');
            return {'count': 1};
          },
          onCancelStaff: (uid, reason) async => calls.add('cancel $uid $reason'),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('HX1-0F4K03J • 1 km • Visakhapatnam'), findsOneWidget);
    expect(find.textContaining('Ravi • STF-NRPM-116-702'), findsOneWidget);
    expect(find.text('With the office (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin-hex-relink-cellA')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lakshmi Kirana'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('admin-hex-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-hex-cancel-cellA')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('admin-hex-cancel-go'))).onPressed, isNull, reason: 'a reason is needed');
    await tester.enterText(find.byKey(const ValueKey('admin-hex-cancel-reason')), 'Left the job');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('admin-hex-cancel-go')));
    await tester.pumpAndSettle();
    expect(calls, ['preview s9', 'relink s9', 'cancel s9 Left the job']);
  });
}
