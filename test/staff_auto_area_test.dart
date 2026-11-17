import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/modules/staffareas/admin_staff_areas.dart';
import 'package:ecommerce_app/modules/staffareas/staffareas_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Owner, 7 Nov 2026: automatic staff area radius from the building density.
void main() {
  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('the app snaps a tap to the same block as the server', () {
    final b = blockOf(17.6683, 82.6121);
    expect([b.blockId, b.latitude, b.longitude], ['B1766_8261', 17.665, 82.615]);
  });

  testWidgets('search, tap the centre, the app sets the radius (no box to change it), stand inside and register', (tester) async {
    size(tester, const Size(420, 2200));
    final previews = <Map<String, dynamic>>[];
    final claims = <Map<String, dynamic>>[];
    var at = const LatLng(17.9, 82.9);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffAutoAreaPage(
          store: Store(),
          search: (q) async => [const FoundPlace(name: 'Main Bazaar', town: 'Narsipatnam', latitude: 17.668, longitude: 82.612, detail: 'Main Bazaar, Narsipatnam')],
          preview: (d) async {
            previews.add(d);
            return {'blockId': 'B1766_8261', 'latitude': 17.665, 'longitude': 82.615, 'radiusKm': 2, 'buildings': 1500, 'densityPerKm2': 477, 'free': true};
          },
          claim: (d) async {
            claims.add(d);
            return {'status': 'booked', 'radiusKm': 2};
          },
          locate: () async => at,
        ),
      ),
    ));
    await tester.enterText(find.byKey(const ValueKey('auto-area-search')), 'Main Bazaar');
    await tester.tap(find.byKey(const ValueKey('auto-area-search-go')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auto-area-place-0')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('auto-area-name'))).controller!.text, 'Main Bazaar');
    // A tap on the map (the map widget is replaced by its callback here).
    final map = tester.widget<AreaPickerMap>(find.byKey(const ValueKey('auto-area-map')));
    map.onTap(const LatLng(17.6683, 82.6121));
    await tester.pumpAndSettle();
    expect(previews.single, {'latitude': 17.6683, 'longitude': 82.6121});
    expect(find.text('Your area: 2 km around the centre'), findsOneWidget);
    expect(find.textContaining('cannot be changed'), findsOneWidget);
    expect(find.textContaining('Radius'), findsNothing, reason: 'no radius box for staff');

    await tester.ensureVisible(find.byKey(const ValueKey('auto-area-register')));
    await tester.tap(find.byKey(const ValueKey('auto-area-register')));
    await tester.pump();
    expect(find.textContaining('Tick "I accept'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('auto-area-terms')), matching: find.byType(Checkbox)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('auto-area-register')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Please go to this area'), findsOneWidget);
    expect(claims, isEmpty);

    at = const LatLng(17.666, 82.616);
    await tester.tap(find.byKey(const ValueKey('auto-area-register')));
    await tester.pumpAndSettle();
    expect(claims.single['latitude'], 17.665);
    expect(claims.single['town'], 'Narsipatnam');
    expect(claims.single.containsKey('radiusKm'), isFalse, reason: 'the phone never sends a radius');
    expect(find.text('This is your area now (2 km).'), findsOneWidget);
  });

  testWidgets('a taken or too-close place says so and cannot be registered', (tester) async {
    size(tester, const Size(420, 2200));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffAutoAreaPage(
          store: Store(),
          preview: (d) async => {'blockId': 'B1', 'latitude': 17.665, 'longitude': 82.615, 'radiusKm': 1, 'buildings': 4000, 'densityPerKm2': 1273, 'free': false, 'problem': 'Too close to "Main Bazaar". Tap a place further away.'},
          claim: (d) async => throw StateError('must not be called'),
        ),
      ),
    ));
    tester.widget<AreaPickerMap>(find.byKey(const ValueKey('auto-area-map'))).onTap(const LatLng(17.6683, 82.6121));
    await tester.pumpAndSettle();
    expect(find.textContaining('Too close to "Main Bazaar"'), findsWidgets);
    await tester.ensureVisible(find.byKey(const ValueKey('auto-area-register')));
    await tester.tap(find.byKey(const ValueKey('auto-area-register')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin: the 4 density bands in plain words, checked and saved', (tester) async {
    size(tester, const Size(420, 3200));
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StaffAreaSettingsForm(settings: const StaffAreaSettings(), onSave: (f) async => saved = f))));
    expect(find.text('Automatic area size'), findsOneWidget);
    expect(find.text('Fewer than the band above'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('staff-density-min-0'))).controller!.text, '1000');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('staff-density-km-3'))).controller!.text, '15');
    await tester.enterText(find.byKey(const ValueKey('staff-density-min-1')), '2000');
    await tester.ensureVisible(find.byKey(const ValueKey('staff-area-settings-save')));
    await tester.tap(find.byKey(const ValueKey('staff-area-settings-save')));
    await tester.pump();
    expect(find.textContaining('fewer buildings than the band above'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('staff-density-min-1')), '400');
    await tester.enterText(find.byKey(const ValueKey('staff-density-km-3')), '20');
    await tester.ensureVisible(find.byKey(const ValueKey('staff-area-settings-save')));
    await tester.tap(find.byKey(const ValueKey('staff-area-settings-save')));
    await tester.pumpAndSettle();
    expect(saved?['densityBands'], [
      {'minPerKm2': 1000, 'radiusKm': 1.0},
      {'minPerKm2': 400, 'radiusKm': 2.0},
      {'minPerKm2': 50, 'radiusKm': 4.0},
      {'minPerKm2': 0, 'radiusKm': 20.0},
    ]);
    expect(tester.takeException(), isNull);
  });
}
