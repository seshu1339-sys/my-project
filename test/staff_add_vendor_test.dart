import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/services/geocoding.dart';
import 'package:ecommerce_app/ui/field_add_vendor_form.dart';
import 'package:ecommerce_app/ui/field_my_additions.dart';

/// Records the server calls (Store.call is the one place every server call goes through).
class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  final calls = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls[name] = data;
    return {'status': 'pending', 'vendorCode': 'VEN-NRPM-116-321'};
  }
}

Position _at(double lat, double lng) => Position(latitude: lat, longitude: lng, timestamp: DateTime(2026, 10, 25), accuracy: 5, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
final _jpeg = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  StaffItemDraft item({bool chosen = true, String price = '30', int photos = 2}) {
    final d = StaffItemDraft();
    if (chosen) d.libraryItem = const Entry('lib-tomato', {'name': 'Tomato'});
    d.price.text = price;
    for (var i = 0; i < photos; i++) {
      d.photos.add(_jpeg);
    }
    return d;
  }

  test('a vendor added by staff needs the location, a name, a phone, 3 photos, and items with a price and 2-3 photos', () {
    List<String> errors({bool location = true, String name = 'Lakshmi Kirana', String phone = '9876543210', int photos = 3, List<StaffItemDraft>? items}) =>
        staffVendorErrors(name: name, phone: phone, address: 'Main Road, Narsipatnam', pincode: '531116', hasLocation: location, vendorPhotos: photos, items: items ?? [item()]);
    expect(errors(), isEmpty);
    expect(errors(location: false), [startsWith('Turn on your location')]);
    expect(errors(name: ''), ["Enter the vendor's name."]);
    expect(errors(phone: '1'), ["Enter the vendor's phone number."]);
    expect(errors(photos: 2), ['Add all 3 photos of the vendor.']);
    expect(errors(items: []), ['Add at least one item the vendor sells.']);
    expect(errors(items: [item(chosen: false)]), ['Item 1: choose the item.']);
    expect(errors(items: [item(), item(price: '')]), ['Item 2: enter the price.']);
    expect(errors(items: [item(photos: 1)]), ['Item 1: add 2 or 3 photos.']);
  });

  test('what is sent to the server', () {
    final out = staffVendorRequest(
      additionId: 'abc12345', name: ' Lakshmi Kirana ', phone: '9876543210', ownerName: '', shopCategory: 'Kirana', address: 'Main Road', pincode: '531116',
      description: '', latitude: 17.66, longitude: 82.61, gpsAddress: 'Main Road, Narsipatnam', items: [item(photos: 3)],
    );
    expect(out['vendor'], containsPair('name', 'Lakshmi Kirana'));
    expect(out['items'], [{'libraryItemId': 'lib-tomato', 'unitType': 'kg', 'quantity': 1, 'price': 30.0, 'photoCount': 3}]);
    expect(out['latitude'], 17.66);
  });

  testWidgets('the form: GPS fills the address, photos, an item from the library with its photos, and it goes to the admin', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _RecordingStore();
    store.catalog['categories'] = const [Entry('cat-vegetables', {'name': 'Vegetables', 'active': true})];
    store.catalog['productImageLibrary'] = const [Entry('lib-tomato', {'name': 'Tomato', 'categoryId': 'cat-vegetables', 'active': true})];
    final taken = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => FieldAddVendorForm(
                store: store,
                locate: () async => _at(17.6685, 82.6126),
                lookUpAddress: (lat, lng) async => const ReverseAddress(text: 'Main Road, Narsipatnam, 531100', pincode: '531100'),
                findPlace: (lat, lng) async => const Place(name: 'Narsipatnam', district: 'Visakhapatnam', state: 'Andhra Pradesh', pincode: '531116', village: false, latitude: 17.67, longitude: 82.61, town: 'Narsipatnam'),
                takePhoto: (additionId, name) async {
                  taken.add(name);
                  return _jpeg;
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
    expect(find.widgetWithText(TextField, 'Main Road, Narsipatnam, 531116'), findsOneWidget, reason: 'the address from the staff GPS');

    // nothing goes without the details
    await tester.tap(find.byKey(const ValueKey('staff-vendor-submit')));
    await tester.pump();
    expect(find.text("• Enter the vendor's name."), findsOneWidget);
    expect(find.text('• Add all 3 photos of the vendor.'), findsOneWidget);
    expect(store.calls, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('staff-vendor-name')), 'Lakshmi Kirana');
    await tester.enterText(find.byKey(const ValueKey('staff-vendor-phone')), '9876543210');
    for (final name in ['vendor_1', 'vendor_2', 'vendor_3']) {
      await tester.tap(find.byKey(ValueKey('staff-photo-$name')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('staff-item-category-0-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vegetables').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('staff-library-0-lib-tomato')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('staff-item-price-0')), '30');
    await tester.tap(find.byKey(const ValueKey('staff-photo-item1_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('staff-photo-item1_2')));
    await tester.pump();
    expect(find.text('Add photo 3 (optional)'), findsOneWidget);
    expect(taken, ['vendor_1', 'vendor_2', 'vendor_3', 'item1_1', 'item1_2']);

    // a second item can be added (up to 2) and removed again
    await tester.tap(find.byKey(const ValueKey('staff-item-add')));
    await tester.pump();
    expect(find.byKey(const ValueKey('staff-item-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-item-add')), findsNothing, reason: 'the vendor item limit is 2');
    await tester.tap(find.byKey(const ValueKey('staff-item-remove-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('staff-item-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('staff-vendor-submit')));
    await tester.pumpAndSettle();
    final sent = store.calls['submitStaffVendor']!;
    expect(sent['vendor'], containsPair('pincode', '531116'));
    expect(sent['latitude'], 17.6685);
    expect(sent['items'], [{'libraryItemId': 'lib-tomato', 'unitType': 'kg', 'quantity': 1, 'price': 30.0, 'photoCount': 2}]);
    expect(find.textContaining('Vendor ID: VEN-NRPM-116-321'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget, reason: 'back to the workspace');
  });

  testWidgets('My vendors: waiting, live with its items and prices, not approved with the reason; a new price for an expired one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 10, 26, 10);
    final renewed = <(String, double)>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StaffAdditionsView(
            now: now,
            additions: const [
              Entry('a1', {'status': 'pending', 'vendorCode': 'VEN-NRPM-116-321', 'vendor': {'name': 'Lakshmi Kirana', 'phone': '9876543210'}, 'submittedAt': '2026-10-26T09:00', 'autoApproveHeld': ['vendor photo 2: this picture is online']}),
              Entry('a2', {'status': 'approved', 'vendorCode': 'VEN-NRPM-116-400', 'vendor': {'name': 'Ravi Fruits', 'phone': '9876500000'}, 'submittedAt': '2026-10-25T09:00'}),
              Entry('a3', {'status': 'rejected', 'decisionReason': 'Photos are blurred', 'vendor': {'name': 'Anil Stores'}, 'submittedAt': '2026-10-24T09:00'}),
            ],
            products: const [
              Entry('p1', {'ownerId': 'a2', 'name': 'Banana', 'unit': '1 kg', 'price': 40, 'priceExpiresAt': '2026-10-26T20:00:00.000'}),
              Entry('p2', {'ownerId': 'a2', 'name': 'Apple', 'unit': '1 kg', 'priceExpired': true, 'priceExpiresAt': '2026-10-26T08:00:00.000'}),
            ],
            onNewPrice: (id, price) async => renewed.add((id, price)),
          ),
        ),
      ),
    ));
    expect(find.text('3 added by you • 1 price to renew'), findsOneWidget);
    expect(find.text('Waiting for the administrator'), findsOneWidget);
    expect(find.text('• vendor photo 2: this picture is online'), findsOneWidget, reason: 'auto-approve on, but the Google check found something');
    expect(find.text('Vendor ID: VEN-NRPM-116-321 • Phone: 9876543210'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Not approved: Photos are blurred'), findsOneWidget);
    expect(find.text('₹40 for 1 kg • valid for 10 h 0 min'), findsOneWidget);
    expect(find.text('Price expired: enter a new price'), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-renew-p1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('staff-renew-p2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('staff-new-price-p2')), '120');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(renewed, [('p2', 120.0)]);
  });
}
