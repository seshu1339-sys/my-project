import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/services/geocoding.dart';
import 'package:ecommerce_app/ui/field_home_page.dart';
import 'package:ecommerce_app/ui/field_registration_form.dart';

/// Records the server calls (Store.call is the one place every server call goes through).
class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  final calls = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls[name] = data;
    return {'status': 'pending'};
  }
}

Position _at(double lat, double lng) => Position(latitude: lat, longitude: lng, timestamp: DateTime(2026, 10, 25), accuracy: 5, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);

void main() {
  test('a staff registration needs a name, a phone, the photo, the location and its pincode', () {
    List<String> errors({String name = 'Kiran Kumar', String phone = '9876543210', bool photo = true, String pin = '531116', bool location = true}) =>
        fieldStaffRegistrationErrors(name: name, phone: phone, hasPhoto: photo, pincode: pin, hasLocation: location);
    expect(errors(), isEmpty);
    expect(errors(location: false), ['Turn on your location (GPS) and capture it.']);
    expect(errors(pin: '5311'), ['Enter a valid six-digit pincode.']);
    expect(errors(photo: false), ['Upload a clear photo of yourself.']);
    expect(errors(phone: '12'), ['Enter a valid contact phone number.']);
  });

  test('what is sent: the name, phone, GPS point, pincode and the area from GPS', () {
    expect(
      fieldStaffRequest(name: ' Kiran Kumar ', phone: '9876543210', latitude: 17.6685, longitude: 82.6126, pincode: '531116', gpsAddress: 'Gandhi Nagar, Narsipatnam, 531116'),
      {'name': 'Kiran Kumar', 'phone': '9876543210', 'latitude': 17.6685, 'longitude': 82.6126, 'pincode': '531116', 'gpsAddress': 'Gandhi Nagar, Narsipatnam, 531116'},
    );
    expect(fieldStaffRequest(name: 'K K', phone: '1', latitude: 1, longitude: 2, pincode: '531116').containsKey('gpsAddress'), isFalse);
  });

  test('a vendor or service-provider login cannot register as staff (the accounts are separate)', () {
    expect(fieldAccountBlock(), isNull);
    expect(fieldAccountBlock(vendorApplication: {'status': 'pending'}), startsWith('This account is a vendor account.'));
    expect(fieldAccountBlock(vendor: {'status': 'approved'}), startsWith('This account is a vendor account.'));
    expect(fieldAccountBlock(quickAccount: {'role': 'vendor'}), startsWith('This account is a vendor account.'));
    expect(fieldAccountBlock(quickAccount: {'role': 'staff'}), isNull);
    expect(fieldAccountBlock(providerApplication: {'status': 'pending'}), startsWith('This account is a service-provider account.'));
    expect(fieldAccountBlock(provider: {'status': 'approved'}), startsWith('This account is a service-provider account.'));
  });

  Future<void> show(WidgetTester tester, Future<Position> Function() locate) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FieldRegistrationForm(
          store: _RecordingStore(),
          locate: locate,
          lookUpAddress: (lat, lng) async => const ReverseAddress(text: 'Gandhi Nagar, Narsipatnam, 531100', pincode: '531100'),
          findPlace: (lat, lng) async => const Place(name: 'Narsipatnam', district: 'Visakhapatnam', state: 'Andhra Pradesh', pincode: '531116', village: false, latitude: 17.67, longitude: 82.61, town: 'Narsipatnam'),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the form captures the location when it opens and fills the pincode from it', (tester) async {
    await show(tester, () async => _at(17.6685, 82.6126));
    expect(find.text('Location captured: 17.66850, 82.61260'), findsOneWidget);
    expect(find.text('Area: Gandhi Nagar, Narsipatnam, 531116'), findsOneWidget, reason: 'the India Post pincode replaces the OpenStreetMap one');
    expect(find.widgetWithText(TextField, '531116'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('staff-name')), 'Kiran Kumar');
    await tester.enterText(find.byKey(const ValueKey('staff-phone')), '9876543210');
    await tester.tap(find.byKey(const ValueKey('staff-submit')));
    await tester.pump();
    expect(find.text('• Upload a clear photo of yourself.'), findsOneWidget);
    expect(find.textContaining('Turn on your location'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without the location the staff member cannot register', (tester) async {
    await show(tester, () async => throw StateError('Location is turned off. Turn it on to register as field staff.'));
    expect(find.text('Location is turned off. Turn it on to register as field staff.'), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-location-required')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('staff-submit')));
    await tester.pump();
    expect(find.text('• Turn on your location (GPS) and capture it.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
