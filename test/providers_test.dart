import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/modules/services/services_page.dart';
import 'package:ecommerce_app/services/geocoding.dart';
import 'package:ecommerce_app/ui/product_page.dart';
import 'package:ecommerce_app/ui/provider_page.dart';
import 'package:ecommerce_app/ui/provider_registration_form.dart';

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

const _types = [
  Entry('type-plumber', {'name': 'Plumber', 'kind': 'serviceType', 'typeId': 'plumber', 'imageFileName': 'plumber.webp', 'order': 1, 'active': true}),
  Entry('type-tutor', {'name': 'Tutor', 'kind': 'serviceType', 'typeId': 'tutor', 'imageFileName': 'tutor.webp', 'order': 2, 'active': true}),
];

Position _at(double lat, double lng) => Position(latitude: lat, longitude: lng, timestamp: DateTime(2026, 10, 25), accuracy: 5, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);

void main() {
  test('a provider application needs a name, mobile, a service, a charge per hour, the address, the photo and the location', () {
    List<String> errors({String name = 'Suresh Kumar', String phone = '9876543210', String? type = 'type-plumber', String rate = '250', String address = 'Gandhi Nagar, Narsipatnam', String pin = '531116', bool photo = true, bool location = true}) =>
        providerApplicationErrors(name: name, phone: phone, serviceTypeId: type, hourlyRate: rate, address: address, pincode: pin, hasPhoto: photo, hasLocation: location);
    expect(errors(), isEmpty);
    expect(errors(type: null), ['Choose your service.']);
    expect(errors(rate: '0'), ['Enter your charge per hour (for example 200).']);
    expect(errors(rate: 'abc'), hasLength(1));
    expect(errors(photo: false), ['Upload your photo.']);
    expect(errors(location: false), ['Turn on your location (GPS) and capture it.']);
    expect(errors(phone: '12'), ['Enter a valid mobile number.']);
  });

  testWidgets('the form: GPS fills the house address and pincode, the service comes from the admin list, and everything goes to the server', (tester) async {
    final store = _RecordingStore();
    store.catalog['services'] = _types;
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProviderRegistrationForm(
          store: store,
          email: 'suresh@example.com',
          previous: const {'status': 'rejected', 'decisionReason': 'Photo unclear', 'photoPath': 'providerApplications/u/photo'},
          locate: () async => _at(17.6685, 82.6126),
          lookUpAddress: (lat, lng) async => const ReverseAddress(text: 'Gandhi Nagar, Narsipatnam, 531100', pincode: '531100'),
          findPlace: (lat, lng) async => const Place(name: 'Narsipatnam', district: 'Visakhapatnam', state: 'Andhra Pradesh', pincode: '531116', village: false, latitude: 17.67, longitude: 82.61, town: 'Narsipatnam'),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Photo unclear'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Gandhi Nagar, Narsipatnam, 531116'), findsOneWidget, reason: 'the India Post pincode replaces the OSM one');
    expect(find.widgetWithText(TextField, '531116'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('provider-name')), 'Suresh Kumar');
    await tester.enterText(find.byKey(const ValueKey('provider-phone')), '9876543210');
    await tester.tap(find.byKey(const ValueKey('provider-service-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plumber').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('provider-rate')), '250');
    await tester.tap(find.byKey(const ValueKey('provider-submit')));
    await tester.pump();
    final sent = store.calls['registerProvider']!;
    expect(sent['serviceTypeId'], 'type-plumber');
    expect(sent['hourlyRate'], 250.0);
    expect(sent['name'], 'Suresh Kumar');
    expect(sent['pincode'], '531116');
    expect(sent['gpsAddress'], 'Gandhi Nagar, Narsipatnam, 531116');
    expect(sent['latitude'], 17.6685);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('waiting for the admin, then live with a "Change charge per hour" button', (tester) async {
    const application = {'name': 'Suresh Kumar', 'serviceName': 'Plumber', 'hourlyRate': 250, 'address': 'Gandhi Nagar', 'pincode': '531116', 'phone': '9876543210'};
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ProviderStatusView(application: {...application, 'status': 'pending'}))));
    expect(find.text('Pending Approval'), findsOneWidget);
    expect(find.byKey(const ValueKey('provider-change-rate')), findsNothing);

    double? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProviderStatusView(application: const {...application, 'status': 'approved'}, onChangeRate: (rate) async => saved = rate))));
    expect(find.text('Your service is live'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('provider-change-rate')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('provider-new-rate')), '300');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 300);
  });

  testWidgets('customers: a provider is listed under the service type and booked by calling (no bag buttons)', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    const provider = Entry('prov-u1', {
      'kind': 'service', 'providerId': 'u1', 'name': 'Suresh Kumar', 'typeId': 'plumber', 'serviceName': 'Plumber', 'price': 250, 'unit': 'per hour',
      'description': 'Plumber • ₹250 per hour', 'phone': '9876543210', 'whatsapp': '919876543210', 'town': 'Narsipatnam', 'stock': 0, 'active': true,
    });
    store.catalog['services'] = [..._types, provider];
    await tester.pumpWidget(MaterialApp(home: ServicesPage(store: store)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Plumber'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Suresh Kumar'), findsOneWidget, reason: 'filed under Plumber by its type, not by words in its name');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: ProductPage(store: store, entry: provider)));
    await tester.pump();
    expect(find.text('Add to bag'), findsNothing);
    expect(find.byKey(const ValueKey('provider-area')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
