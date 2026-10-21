import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/ui/field_entry_form.dart';

Position _at(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 10, 21),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

const _raj = Place(
  name: 'Rajahmundry', district: 'East Godavari', state: 'Andhra Pradesh', pincode: '533101',
  village: false, latitude: 17, longitude: 81.8, town: 'Rajahmundry',
);

Future<void> _open(WidgetTester tester, {Future<Place?> Function(double, double)? findTown, Future<Position> Function()? locate}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  await tester.pumpWidget(MaterialApp(home: FieldEntryForm(store: store, locate: locate ?? () async => _at(17.0005, 81.804), findPlace: findTown ?? (lat, lng) async => _raj)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('New shop'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a new shop\'s pincode is filled from the GPS fix, with the nearest town shown', (tester) async {
    await _open(tester);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('field-shop-pincode'))).controller!.text, '533101');
    expect(find.text('Nearest town from your location: Rajahmundry, East Godavari (533101)'), findsOneWidget);
  });

  testWidgets('what the staff member typed is never overwritten, but a GPS-filled pincode follows a new fix', (tester) async {
    var calls = 0;
    await _open(tester, findTown: (lat, lng) async => ++calls == 1 ? _raj : const Place(name: 'Kakinada', district: 'East Godavari', state: 'Andhra Pradesh', pincode: '533001', village: false, latitude: 16.9, longitude: 82.2, town: 'Kakinada'));
    // GPS filled it; recapturing moves it to the new town
    await tester.ensureVisible(find.text('Recapture location'));
    await tester.tap(find.text('Recapture location'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('field-shop-pincode'))).controller!.text, '533001');
    // now they type their own: a later fix keeps it
    await tester.enterText(find.byKey(const ValueKey('field-shop-pincode')), '500001');
    await tester.ensureVisible(find.text('Recapture location'));
    await tester.tap(find.text('Recapture location'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('field-shop-pincode'))).controller!.text, '500001');
  });

  testWidgets('outside Andhra Pradesh / Telangana or with no directory the pincode stays empty and can be typed', (tester) async {
    await _open(tester, findTown: (lat, lng) async => null);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('field-shop-pincode'))).controller!.text, isEmpty);
    expect(find.byKey(const ValueKey('field-nearest-town')), findsNothing);
    await _open(tester, findTown: (lat, lng) async => throw StateError('directory down'));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('field-shop-pincode'))).controller!.text, isEmpty);
  });
}
