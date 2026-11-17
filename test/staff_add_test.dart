import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/modules/stafflinks/stafflinks_module.dart';
import 'package:ecommerce_app/modules/transport/transport_page.dart';
import 'package:ecommerce_app/ui/field_add_page.dart';

// Staff app > Add (6 Nov 2026): vendors and providers register themselves; staff link them by ID within 30 minutes.
void main() {
  Future<Store> show(WidgetTester tester, {bool real = false}) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MaterialApp(
      home: real
          ? FieldAddPage(store: store)
          : FieldAddPage(
              store: store,
              vendorPage: (_) => const Scaffold(body: Text('VENDOR LINK')),
              servicesPage: (_) => const Scaffold(body: Text('PROVIDER LINK')),
            ),
    ));
    return store;
  }

  testWidgets('Add: Vendor, Services and Transport; Vendor and Services open the link by ID', (tester) async {
    final store = await show(tester);
    expect(find.text('Who registered with your help?'), findsOneWidget);
    expect(find.textContaining('within 30 minutes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('field-add-vendor')));
    await tester.pumpAndSettle();
    expect(find.text('VENDOR LINK'), findsOneWidget);
    Navigator.of(tester.element(find.text('VENDOR LINK'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('field-add-services')));
    await tester.pumpAndSettle();
    expect(find.text('PROVIDER LINK'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the real Vendor page is the link page, with no shop or price fields', (tester) async {
    final store = await show(tester, real: true);
    await tester.tap(find.byKey(const ValueKey('field-add-vendor')));
    await tester.pumpAndSettle();
    expect(find.text('Link a vendor'), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-link-code')), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget, reason: 'only the ID: no name, phone, photo or price field');
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

  testWidgets('linking: a wrong ID is refused here, the server answer is shown, success says who is linked', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    final sent = <String>[];
    var answer = <String, dynamic>{'name': 'Lakshmi Kirana'};
    Object? fail;
    await tester.pumpWidget(MaterialApp(
      home: StaffLinkPage(store: store, provider: false, onLink: (code) async {
        sent.add(code);
        final error = fail;
        if (error != null) throw error;
        return answer;
      }),
    ));
    await tester.enterText(find.byKey(const ValueKey('staff-link-code')), 'SRV-NRPM-116-001');
    await tester.tap(find.byKey(const ValueKey('staff-link-save')));
    await tester.pump();
    expect(find.textContaining('Enter the Vendor ID'), findsOneWidget, reason: 'a provider ID on the vendor page');
    expect(sent, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('staff-link-code')), ' ven-nrpm-116-325 ');
    await tester.tap(find.byKey(const ValueKey('staff-link-save')));
    await tester.pumpAndSettle();
    expect(sent, ['VEN-NRPM-116-325']);
    expect(find.text('Linked: Lakshmi Kirana (VEN-NRPM-116-325) is now registered by you.'), findsOneWidget);

    fail = Exception('More than 30 minutes have passed since this registration');
    await tester.enterText(find.byKey(const ValueKey('staff-link-code')), 'VEN-NRPM-116-400');
    await tester.tap(find.byKey(const ValueKey('staff-link-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('30 minutes have passed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  test('the staff member reads how many items a linked vendor has, how many were updated today and the last update', () {
    final now = DateTime.utc(2026, 11, 6, 6);
    final u = linkedUpdates([
      {'priceSetAt': '2026-11-06T02:00:00Z'},
      {'priceSetAt': '2026-11-04T02:00:00Z'},
      {},
    ], now);
    expect(u.items, 3);
    expect(u.updatedToday, 1);
    expect(u.lastUpdate, DateTime.utc(2026, 11, 6, 2));
  });

  testWidgets('"Vendors I registered" is read only: names, IDs, updates, and no edit button', (tester) async {
    final link = StaffLink(id: 'vendor_v1', kind: 'vendor', accountUid: 'v1', code: 'VEN-NRPM-116-325', name: 'Lakshmi Kirana', staffUid: 's1', staffCode: 'STF-NRPM-116-482', staffName: 'Kiran', linkedAt: DateTime(2026, 11, 6));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StaffLinkedListView(
            links: [link],
            now: DateTime.utc(2026, 11, 6, 6),
            updates: (_) => Stream.value([
              {'priceSetAt': '2026-11-06T02:00:00Z'},
              {'priceSetAt': '2026-11-05T02:00:00Z'},
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Lakshmi Kirana'), findsOneWidget);
    expect(find.textContaining('VEN-NRPM-116-325 • linked 06/11/2026'), findsOneWidget);
    expect(find.textContaining('2 items • 1 updated today'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('admin: "Registered by" with the Staff ID, or self-registered', (tester) async {
    final link = StaffLink(id: 'vendor_v1', kind: 'vendor', accountUid: 'v1', code: 'VEN-NRPM-116-325', name: 'Lakshmi Kirana', staffUid: 's1', staffCode: 'STF-NRPM-116-482', staffName: 'Kiran', linkedAt: DateTime(2026, 11, 6));
    final removed = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RegisteredByView(link: link, onRemove: (l) async => removed.add(l.id)))));
    expect(find.text('Registered by STF-NRPM-116-482 (Kiran) on 06/11/2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('registered-by-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('registered-by-remove-confirm')));
    await tester.pumpAndSettle();
    expect(removed, ['vendor_v1']);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RegisteredByView(link: null))));
    expect(find.text('Self-registered (no staff link)'), findsOneWidget);
  });
}
