import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/services/geocoding.dart';
import 'package:ecommerce_app/ui/vendor.dart';

/// Records the registerVendor call the form makes (Store.call is the one place every server call goes through).
class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  final calls = <String, Map<String, dynamic>>{};
  int get registrations => calls.containsKey('registerVendor') ? 1 : 0;
  String get lastGpsAddress => '${calls['registerVendor']?['gpsAddress'] ?? ''}';
  String get lastAddress => '${calls['registerVendor']?['address'] ?? ''}';
  String get lastPincode => '${calls['registerVendor']?['pincode'] ?? ''}';

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls[name] = data;
    return {'status': 'pending'};
  }
}

Position _at(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 10, 25),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  test('the readable address of a reverse-geocoding result', () {
    final full = reverseAddressFromJson({
      'display_name': 'Main Road, Krishna Bazar, Narsipatnam, Anakapalli, Andhra Pradesh, 531116, India',
      'address': {'road': 'Main Road', 'suburb': 'Krishna Bazar', 'town': 'Narsipatnam', 'postcode': '531116', 'state': 'Andhra Pradesh'},
    })!;
    expect(full.text, 'Main Road, Krishna Bazar, Narsipatnam, 531116');
    expect(full.pincode, '531116');
    expect(full.town, 'Narsipatnam');
    final noPin = reverseAddressFromJson({'address': {'road': 'Bus Stand Road', 'city': 'Tuni'}})!;
    expect(noPin.text, 'Bus Stand Road, Tuni');
    expect(noPin.pincode, '');
    expect(reverseAddressFromJson({'display_name': 'Somewhere far', 'address': {'country': 'India'}})!.text, 'Somewhere far');
    expect(reverseAddressFromJson('not json'), isNull);
  });

  testWidgets('the GPS fills the shop address and pincode (pincode from the India Post directory), the vendor can correct them, and the GPS address is sent along', (tester) async {
    final store = _RecordingStore();
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VendorRegistrationForm(
          store: store,
          email: 'vendor@example.com',
          previous: const {'status': 'rejected', 'vendorPhotoPath': 'a', 'shopPhotoPath': 'b'},
          locate: () async => _at(17.6685, 82.6126),
          // OpenStreetMap's postcode here is wrong (531100); the directory's pincode for the point replaces it
          lookUpAddress: (lat, lng) async => const ReverseAddress(text: 'Main Road, Krishna Bazar, Narsipatnam, 531100', pincode: '531100', town: 'Narsipatnam'),
          findPlace: (lat, lng) async => const Place(name: 'Krishna Bazar (Narsipatnam)', district: 'Visakhapatnam', state: 'Andhra Pradesh', pincode: '531118', village: false, latitude: 17.67, longitude: 82.61, town: 'Krishna Bazar (Narsipatnam)'),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Main Road, Krishna Bazar, Narsipatnam, 531118'), findsOneWidget, reason: 'the address box is filled from the GPS');
    expect(find.widgetWithText(TextField, '531118'), findsOneWidget, reason: 'the pincode box too, from the directory');
    expect(find.byKey(const ValueKey('gps-address')), findsOneWidget);
    expect(find.byKey(const ValueKey('location-required')), findsNothing);

    // the vendor corrects the address and fills the rest
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Ravi Kumar');
    await tester.enterText(fields.at(1), '9876543210');
    await tester.enterText(fields.at(2), 'Ravi Stores');
    await tester.enterText(fields.at(3), 'Kirana');
    await tester.enterText(fields.at(4), 'Shop 4, Main Road, Krishna Bazar, Narsipatnam');
    await tester.enterText(fields.at(6), 'Rice, dal and oil at fair prices');
    await tester.tap(find.text('Submit for approval'));
    await tester.pump();
    expect(store.registrations, 1);
    expect(store.lastAddress, 'Shop 4, Main Road, Krishna Bazar, Narsipatnam', reason: 'the corrected address is kept');
    expect(store.lastPincode, '531118');
    expect(store.lastGpsAddress, 'Main Road, Krishna Bazar, Narsipatnam, 531118', reason: 'the admin also sees the GPS address');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without location the form says registration needs it and submits nothing', (tester) async {
    final store = _RecordingStore();
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VendorRegistrationForm(
          store: store,
          email: 'vendor@example.com',
          previous: const {'status': 'rejected', 'vendorPhotoPath': 'a', 'shopPhotoPath': 'b'},
          locate: () async => throw StateError('Location services are turned off.'),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('location-required')), findsOneWidget);
    expect(find.text('Location services are turned off.'), findsOneWidget);
    await tester.tap(find.text('Submit for approval'));
    await tester.pump();
    expect(find.text("• Capture the shop's GPS location."), findsOneWidget);
    expect(store.registrations, 0);
  });
}
