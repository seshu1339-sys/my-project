// Renders the real MarketApp and navigates through the real UI (Shops tab ->
// "Search products near me") to confirm location-based product search
// actually reaches customers, not just that its matching logic is correct in
// isolation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';

// Roughly Bengaluru MG Road.
const _customerLat = 12.9716, _customerLng = 77.5946;
// A shop ~2.1km away (within a 5km radius, outside a 2km radius).
const _shopLat = 12.99, _shopLng = 77.60;

Future<Store> _seededStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  // The demo catalog seeds its own sample shops/products (including one at
  // the exact customer coordinates used below); clear them so only this
  // test's own, deliberately-placed shop/product can match.
  store.catalog['shops']?.clear();
  store.catalog['products']?.clear();
  await store.setLocation('', 'Test location', lat: _customerLat, lng: _customerLng);
  await store.save(
    'shops',
    const Entry('shop1', {
      'name': 'Nearby General Store',
      'address': '12 MG Road',
      'latitude': _shopLat,
      'longitude': _shopLng,
    }),
  );
  await store.save(
    'products',
    const Entry('p1', {'name': 'Fresh Bread', 'price': 50, 'shopId': 'shop1'}),
  );
  return store;
}

Future<void> _openSearchPage(WidgetTester tester, Store store) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MarketApp(store: store));
  await tester.pump();
  await tester.tap(find.byIcon(Icons.storefront_outlined).hitTestable());
  await tester.pumpAndSettle();
  await tester.tap(find.text('Search products near me'));
  await tester.pumpAndSettle();
}

/// The product list sits below the map inside a scrollable; a plain
/// `ListView(children: […])`'s sliver children past the current viewport
/// aren't built until scrolled into view (find.text can't see them yet).
/// Jumping the results ListView's own ScrollableState straight to the bottom
/// sidesteps two issues with a drag-based approach: (1) the previous route
/// (ShopsPage) stays mounted in the Navigator stack with its own
/// ListView/Scrollable, so an unscoped scrollable finder can target the
/// wrong one; (2) a synthetic drag centered on the page can land on the
/// Slider above the results and get captured by it instead of scrolling.
Future<void> _scrollToResultsEnd(WidgetTester tester) async {
  final state = tester.state<ScrollableState>(
    find.descendant(
      of: find.byKey(const Key('product-search-results')),
      matching: find.byType(Scrollable),
    ),
  );
  state.position.jumpTo(state.position.maxScrollExtent);
  await tester.pump();
}

void main() {
  testWidgets('a shop within the search radius shows its products, with price and distance', (
    tester,
  ) async {
    final store = await _seededStore();
    // Default radius resolves to the preset nearest searchRadiusDefaultKm
    // (5), so the shop at ~2.1km must be included.
    await store.save('settings', const Entry('business', {'name': 'Local Market', 'searchRadiusDefaultKm': 5}));
    await _openSearchPage(tester, store);

    await _scrollToResultsEnd(tester);
    expect(find.text('Fresh Bread'), findsOneWidget);
    expect(find.textContaining('₹50'), findsOneWidget);
    expect(find.textContaining('km'), findsWidgets);
    expect(find.textContaining('Nearby General Store'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('a shop outside the search radius is excluded', (tester) async {
    final store = await _seededStore();
    // Default radius resolves to the preset nearest searchRadiusDefaultKm
    // (2), so the shop at ~2.1km must be excluded.
    await store.save('settings', const Entry('business', {'name': 'Local Market', 'searchRadiusDefaultKm': 2}));
    await _openSearchPage(tester, store);

    expect(find.text('Fresh Bread'), findsNothing);
    expect(find.textContaining('No products found in this radius'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('admin-configured radius presets are honored instead of the hardcoded defaults', (
    tester,
  ) async {
    final store = await _seededStore();
    await store.save(
      'settings',
      const Entry('business', {'name': 'Local Market', 'searchRadiusPresetsKm': '1,4', 'searchRadiusDefaultKm': 4}),
    );
    await _openSearchPage(tester, store);

    // Nearest preset to a default of 4 is 4 itself; the ~2.1km shop is inside it.
    expect(find.text('Search radius: 4 km'), findsOneWidget);
    await _scrollToResultsEnd(tester);
    expect(find.text('Fresh Bread'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('tapping a matching product opens its own product detail page', (tester) async {
    final store = await _seededStore();
    await store.save('settings', const Entry('business', {'name': 'Local Market', 'searchRadiusDefaultKm': 5}));
    await _openSearchPage(tester, store);

    await _scrollToResultsEnd(tester);
    await tester.tap(find.text('Fresh Bread').first);
    await tester.pumpAndSettle();
    // The product detail page repeats the name as its own heading, so it now
    // appears at least twice (the search result tile plus the detail page).
    expect(find.text('Fresh Bread'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
