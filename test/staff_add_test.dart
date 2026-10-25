import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/modules/transport/transport_page.dart';
import 'package:ecommerce_app/ui/field_add_page.dart';

const _types = [
  Entry('type-tutor', {'name': 'Tutor', 'kind': 'serviceType', 'typeId': 'tutor', 'imageFileName': 'tutor.webp', 'order': 2, 'active': true}),
  Entry('type-plumber', {'name': 'Plumber', 'kind': 'serviceType', 'typeId': 'plumber', 'imageFileName': 'plumber.webp', 'order': 1, 'active': true}),
  Entry('type-electrician', {'name': 'Electrician', 'kind': 'serviceType', 'typeId': 'electrician', 'imageFileName': 'electrician.webp', 'order': 3, 'active': true}),
  Entry('prov-u1', {'name': 'Suresh Kumar', 'kind': 'service', 'typeId': 'plumber', 'active': true}),
];

void main() {
  Future<Store> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['services'] = _types;
    await tester.pumpWidget(MaterialApp(
      home: FieldAddPage(
        store: store,
        vendorForm: (_) => const Scaffold(body: Text('VENDOR FORM')),
        serviceForm: (_, type) => Scaffold(body: Text('SERVICE FORM: ${type.text('name')}')),
      ),
    ));
    return store;
  }

  testWidgets('Add: Vendor, Services and Transport; Vendor opens the vendor form', (tester) async {
    final store = await show(tester);
    expect(find.text('What are you adding?'), findsOneWidget);
    expect(find.byKey(const ValueKey('field-add-vendor')), findsOneWidget);
    expect(find.byKey(const ValueKey('field-add-services')), findsOneWidget);
    expect(find.byKey(const ValueKey('field-add-transport')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('field-add-vendor')));
    await tester.pumpAndSettle();
    expect(find.text('VENDOR FORM'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Services: the admin\'s service types in their order (not the providers), searchable; choosing one opens its form', (tester) async {
    final store = await show(tester);
    await tester.tap(find.byKey(const ValueKey('field-add-services')));
    await tester.pumpAndSettle();
    expect(find.text('Which service?'), findsOneWidget);
    final names = [for (final id in ['type-plumber', 'type-tutor', 'type-electrician']) tester.getTopLeft(find.byKey(ValueKey('field-service-type-$id'))).dy];
    expect(names[0] < names[1] && names[1] < names[2], isTrue, reason: 'in the admin\'s order: Plumber, Tutor, Electrician');
    expect(find.text('Suresh Kumar'), findsNothing, reason: 'a provider is not a service type');
    await tester.enterText(find.byKey(const ValueKey('field-service-search')), 'plu');
    await tester.pump();
    expect(find.byKey(const ValueKey('field-service-type-type-tutor')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('field-service-type-type-plumber')));
    await tester.pumpAndSettle();
    expect(find.text('SERVICE FORM: Plumber'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Transport is its own module and says it is coming soon', (tester) async {
    final store = await show(tester);
    await tester.tap(find.byKey(const ValueKey('field-add-transport')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transport-coming-soon')), findsOneWidget);
    expect(find.text(transportComingSoon), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
