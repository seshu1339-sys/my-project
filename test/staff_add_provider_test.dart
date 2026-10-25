import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/services/geocoding.dart';
import 'package:ecommerce_app/ui/field_add_provider_form.dart';
import 'package:ecommerce_app/ui/field_my_additions.dart';
import 'package:ecommerce_app/ui/provider_page.dart';

/// Records the server calls (Store.call is the one place every server call goes through).
class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  final calls = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls[name] = data;
    return {'status': 'pending', 'providerCode': 'SRV-NRPM-116-208'};
  }
}

Position _at(double lat, double lng) => Position(latitude: lat, longitude: lng, timestamp: DateTime(2026, 10, 25), accuracy: 5, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
const _plumber = Entry('type-plumber', {'name': 'Plumber', 'kind': 'serviceType', 'typeId': 'plumber'});

void main() {
  test('a provider added by staff needs the location, a name, a phone, a charge per hour and 2-3 work photos', () {
    List<String> errors({bool location = true, String name = 'Suresh Kumar', String phone = '9876543210', String rate = '250', int photos = 2}) =>
        staffProviderErrors(name: name, phone: phone, hourlyRate: rate, pincode: '531116', hasLocation: location, workPhotos: photos);
    expect(errors(), isEmpty);
    expect(errors(location: false), [startsWith('Turn on your location')]);
    expect(errors(name: 'S'), ["Enter the provider's name."]);
    expect(errors(phone: ''), ["Enter the provider's phone number."]);
    expect(errors(rate: '0'), ['Enter the charge per hour (for example 200).']);
    expect(errors(photos: 1), ['Add 2 or 3 photos of their work.']);
    final sent = staffProviderRequest(
      additionId: 'abc12345', name: ' Suresh Kumar ', phone: '9876543210', address: '', pincode: '531116', serviceTypeId: 'type-plumber',
      hourlyRate: '250', latitude: 17.6, longitude: 82.6, gpsAddress: '', photoCount: 3,
    );
    expect(sent, {'additionId': 'abc12345', 'provider': {'name': 'Suresh Kumar', 'phone': '9876543210', 'address': '', 'pincode': '531116'}, 'serviceTypeId': 'type-plumber', 'hourlyRate': 250.0, 'latitude': 17.6, 'longitude': 82.6, 'photoCount': 3});
  });

  testWidgets('the form: the chosen service, GPS, name, phone, charge per hour and work photos go to the admin; then back to the start', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _RecordingStore();
    final taken = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => FieldAddProviderForm(
                store: store,
                serviceType: _plumber,
                locate: () async => _at(17.6685, 82.6126),
                lookUpAddress: (lat, lng) async => const ReverseAddress(text: 'Gandhi Nagar, Narsipatnam, 531100', pincode: '531100'),
                findPlace: (lat, lng) async => const Place(name: 'Narsipatnam', district: 'Visakhapatnam', state: 'Andhra Pradesh', pincode: '531116', village: false, latitude: 17.67, longitude: 82.61, town: 'Narsipatnam'),
                takePhoto: (additionId, name) async {
                  taken.add(name);
                  return _png;
                },
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add a Plumber'), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-provider-service')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('staff-provider-submit')));
    await tester.pump();
    expect(find.text("• Enter the provider's name."), findsOneWidget);
    expect(find.text('• Add 2 or 3 photos of their work.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('staff-provider-name')), 'Suresh Kumar');
    await tester.enterText(find.byKey(const ValueKey('staff-provider-phone')), '9876543210');
    await tester.enterText(find.byKey(const ValueKey('staff-provider-rate')), '250');
    await tester.tap(find.byKey(const ValueKey('staff-photo-work_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('staff-photo-work_2')));
    await tester.pump();
    expect(find.text('Add photo 3 (optional)'), findsOneWidget);
    expect(taken, ['work_1', 'work_2']);
    await tester.tap(find.byKey(const ValueKey('staff-provider-submit')));
    await tester.pumpAndSettle();
    final sent = store.calls['submitStaffProvider']!;
    expect(sent['serviceTypeId'], 'type-plumber');
    expect(sent['hourlyRate'], 250.0);
    expect(sent['photoCount'], 2);
    expect(sent['provider'], containsPair('pincode', '531116'));
    expect(sent['latitude'], 17.6685);
    expect(find.textContaining('Provider ID: SRV-NRPM-116-208'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('My vendors and services shows a provider with the service, the charge and the Provider ID', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffAdditionsView(
          now: DateTime(2026, 10, 26),
          additions: const [
            Entry('p1', {'kind': 'provider', 'status': 'approved', 'providerCode': 'SRV-NRPM-116-208', 'serviceName': 'Plumber', 'hourlyRate': 250, 'provider': {'name': 'Suresh Kumar', 'phone': '9876543210'}}),
          ],
          products: const [],
          onNewPrice: (id, price) async {},
        ),
      ),
    ));
    expect(find.text('My vendors and services'), findsOneWidget);
    expect(find.text('Suresh Kumar'), findsOneWidget);
    expect(find.text('Plumber • ₹250 per hour'), findsOneWidget);
    expect(find.text('Provider ID: SRV-NRPM-116-208 • Phone: 9876543210'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('a provider who registered themselves sees their Provider ID', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ProviderStatusView(application: {'status': 'pending', 'name': 'Suresh Kumar', 'providerCode': 'SRV-NRPM-116-042'}))));
    expect(find.text('Provider ID: SRV-NRPM-116-042'), findsOneWidget);
  });
}
