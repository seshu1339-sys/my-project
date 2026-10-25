import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/modules/services/services_page.dart';
import 'package:ecommerce_app/ui/admin_fields.dart';

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  return store;
}

void main() {
  test('services are read from their own collection and never listed as products', () async {
    final store = await _store();
    store.catalog['products'] = const [
      Entry('rice', {'name': 'Rice', 'kind': 'product', 'active': true}),
      Entry('old-svc', {'name': 'Old service copy', 'kind': 'service', 'active': true}), // not deleted from products yet
    ];
    store.catalog['services'] = const [
      Entry('plumbing', {'name': 'Plumbing visit', 'kind': 'service', 'active': true}),
      Entry('type-plumber', {'name': 'Plumber', 'kind': 'serviceType', 'active': true, 'order': 1}),
      Entry('hidden', {'name': 'Hidden service', 'kind': 'service', 'active': false}),
    ];
    expect(store.visibleProducts().map((e) => e.id), ['rice'], reason: 'no service in products');
    expect(store.visibleServices().map((e) => e.id), ['plumbing'], reason: 'listings only, active only, no service types');
    expect(store.serviceTypes().map((e) => e.id), ['type-plumber']);
    expect(store.item('plumbing')?.text('name'), 'Plumbing visit', reason: 'the bag and links find a service');
    expect(store.item('rice')?.text('name'), 'Rice');
    expect(store.product('plumbing'), isNull);
    expect(store.service('type-plumber'), isNull, reason: 'a service type is not a bookable listing');
    store.dispose();
  });

  test('the demo catalog keeps services out of products', () {
    final demo = demoCatalog();
    expect(demo['products']!.where((e) => e.text('kind') == 'service'), isEmpty);
    expect(demo['services']!, isNotEmpty);
    expect(demo['services']!.every((e) => e.text('kind') == 'service'), isTrue);
    expect(collections, contains('services'));
  });

  test('the admin has a Services section with its own form, and the Products form can no longer make a service', () {
    expect(adminSections['services'], 'Services');
    expect(fields['services'], isNotNull);
    expect(fields['services']!.containsKey('kind'), isFalse, reason: 'a listing is always a service');
    expect(adminSections['products'], 'Products');
  });

  testWidgets('the Services page lists the service types of the services collection, and a type\'s listings', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    store.catalog['services'] = const [
      Entry('type-plumber', {'name': 'Plumber', 'kind': 'serviceType', 'typeId': 'plumber', 'imageFileName': 'plumber.webp', 'order': 1, 'active': true}),
      Entry('type-tutor', {'name': 'Tutor', 'kind': 'serviceType', 'typeId': 'tutor', 'imageFileName': 'tutor.webp', 'order': 2, 'active': true}),
      Entry('svc-plumbing', {'name': 'Plumbing Visit', 'kind': 'service', 'active': true, 'price': 100}),
    ];
    await tester.pumpWidget(MaterialApp(home: ServicesPage(store: store)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Plumber'), findsOneWidget);
    expect(find.text('Tutor'), findsOneWidget);
    expect(find.text('Electrician'), findsNothing, reason: 'only the types in the collection');
    await tester.tap(find.text('Plumber'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Plumbing Visit'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the home page Local Services section shows service listings from the services collection', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    store.catalog['products'] = [];
    store.catalog['services'] = const [Entry('svc-mason', {'name': 'Mason Service', 'kind': 'service', 'active': true, 'price': 500, 'unit': 'per visit'})];
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.text('Mason Service'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
