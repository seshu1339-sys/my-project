import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/modules/services/service_categories.dart';
import 'package:ecommerce_app/modules/services/services_page.dart';

void main() {
  // The real bundled photos decode during these tests (a plain `pump()`
  // settles that fine; `pumpAndSettle()` can see decode-related frames as
  // "never settling" across tests sharing one image cache) -- cleared
  // between tests so one test's decoded images can never bleed into the
  // next and cause flakiness.
  tearDown(() {
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  Future<Store> openStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['products'] = [];
    return store;
  }

  // Tall enough that all 30 A-Z rows mount without needing to scroll --
  // the 30-item list is sorted alphabetically (not by the JSON's original
  // display_order), so "Plumber" (near the bottom, P) would otherwise be
  // off-screen at a default test viewport while "Electrician" (E, near
  // the top) is not.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // The services_list.json read is real file I/O, not fake-clock-driven --
  // `tester.runAsync` is the framework's own way to let a widget test
  // genuinely wait on that (a plain `pump()`/`settle()` loop only ever
  // advances the fake clock, so it can only "work" by timing coincidence,
  // not by actually waiting for the read to finish).
  Future<void> pumpServicesPage(WidgetTester tester, Store store) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: ServicesPage(store: store)));
      await settle(tester);
    });
  }

  testWidgets('shows every service type as a vertical A-Z list, not a grid', (
    tester,
  ) async {
    useTallViewport(tester);
    final store = await openStore();
    await pumpServicesPage(tester, store);

    expect(find.byType(ListView), findsOneWidget);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data!)
        .toList();
    expect(titles, hasLength(30));
    final sorted = [...titles]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    expect(
      titles,
      sorted,
      reason: 'the list must already be in alphabetical (A-Z) order',
    );
  });

  testWidgets('typing filters the list live, with no submit needed', (
    tester,
  ) async {
    useTallViewport(tester);
    final store = await openStore();
    await pumpServicesPage(tester, store);

    expect(find.text('Plumber'), findsOneWidget);
    expect(find.text('Electrician'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'plu');
    await settle(tester);

    expect(find.text('Plumber'), findsOneWidget);
    expect(find.text('Electrician'), findsNothing);
  });

  testWidgets(
    'tapping a service type drills into its own vendor listings, matched by name; back returns to the full A-Z list',
    (tester) async {
      useTallViewport(tester);
      final store = await openStore();
      await store.save(
        'products',
        const Entry('s1', {
          'name': 'Quick Electrician Visit',
          'kind': 'service',
          'active': true,
        }),
      );
      await store.save(
        'products',
        const Entry('s2', {
          'name': 'Home Plumbing Fix',
          'kind': 'service',
          'active': true,
        }),
      );

      await pumpServicesPage(tester, store);

      await tester.tap(find.widgetWithText(ListTile, 'Electrician'));
      await settle(tester);

      expect(find.text('Quick Electrician Visit'), findsOneWidget);
      expect(find.text('Home Plumbing Fix'), findsNothing);
      expect(
        find.text('Plumber'),
        findsNothing,
        reason: 'drilled in, not showing the full type list anymore',
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await settle(tester);

      expect(find.text('Plumber'), findsOneWidget);
      expect(find.text('Electrician'), findsOneWidget);
    },
  );

  testWidgets(
    'a newly-added vendor service appears automatically inside its matching type, with no page reload',
    (tester) async {
      useTallViewport(tester);
      final store = await openStore();
      await pumpServicesPage(tester, store);

      await tester.tap(find.widgetWithText(ListTile, 'Carpenter'));
      await settle(tester);
      expect(find.text('No matching services available.'), findsOneWidget);

      await store.save(
        'products',
        const Entry('s3', {
          'name': 'Custom Carpenter Work',
          'kind': 'service',
          'active': true,
        }),
      );
      await settle(tester);

      expect(find.text('Custom Carpenter Work'), findsOneWidget);
    },
  );

  test(
    'categoryServiceListings matches a vendor\'s own wording via shared word stem, not just exact substring',
    () async {
      final store = Store();
      store.catalog['products'] = [
        const Entry('s1', {'name': 'Plumbing visit', 'kind': 'service'}),
        const Entry('s2', {'name': 'Quick Carpentry', 'kind': 'service'}),
        const Entry('s3', {'name': 'Car wash', 'kind': 'service'}),
      ];
      const plumber = ServiceCategory(
        id: 'plumber',
        displayName: 'Plumber',
        imageFileName: 'plumber.webp',
        displayOrder: 1,
      );
      const carMechanic = ServiceCategory(
        id: 'car_mechanic',
        displayName: 'Car Mechanic',
        imageFileName: 'car_mechanic.webp',
        displayOrder: 25,
      );

      final plumberMatches = categoryServiceListings(store, plumber);
      expect(plumberMatches.map((e) => e.id), ['s1']);

      final carMatches = categoryServiceListings(store, carMechanic);
      expect(
        carMatches,
        isEmpty,
        reason:
            '"car" is too short/generic to count alone -- "Car wash" must not fall under Car Mechanic just because both start with "car"',
      );
    },
  );
}
