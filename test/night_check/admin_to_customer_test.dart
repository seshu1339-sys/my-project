// NIGHT CHECK (11 Nov 2026): what the admin saves (settings/business, settings/scrollingText, settings/areaNames, promotions, shops,
// products) really shows on the customer website and in the customer Android app (the real MarketApp, demo store). Prints one
// VISIBLE line per check for NIGHT_CHECK_REPORT.md. Does not change any app code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/android_layout.dart';

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['settings'] = [
    ...store.entries('settings').where((e) => !{'business', 'scrollingText'}.contains(e.id)),
    const Entry('business', {
      'name': 'NightCheck Market', 'tagline': 'NIGHT TAGLINE', 'radiusKm': 10, 'headerContact': 'NIGHT CONTACT 99999',
      'noOffersMessage': 'NIGHT no offers near {town}', 'enabledLanguages': 'en,te',
    }),
    const Entry('scrollingText', {'name': 'Scrolling text', 'text': 'NIGHT SCROLLING TEXT', 'active': true}),
  ];
  store.catalog['shops'] = const [
    Entry('kpl', {'name': 'Kancharapalem Kirana', 'latitude': 17.735, 'longitude': 83.280, 'active': true}),
    Entry('far', {'name': 'Narsipatnam Store', 'latitude': 17.667, 'longitude': 82.612, 'active': true}),
  ];
  store.catalog['products'] = const [
    Entry('p-near', {'name': 'NIGHT Rice', 'price': 40, 'compareAtPrice': 55, 'shopId': 'kpl', 'stock': 9, 'kind': 'product', 'active': true}),
    Entry('p-far', {'name': 'FAR Dal', 'price': 90, 'compareAtPrice': 99, 'shopId': 'far', 'stock': 9, 'kind': 'product', 'active': true}),
  ];
  store.catalog['promotions'] = const [
    Entry('near-offer', {'name': 'NIGHT NEAR OFFER', 'placement': 'carousel', 'radiusShopId': 'kpl', 'active': true, 'order': 1}),
    Entry('general', {'name': 'NIGHT GENERAL OFFER', 'placement': 'carousel', 'active': true, 'order': 2}),
  ];
  await store.setLocation('530008', '', lat: 17.734, lng: 83.279, town: 'Visakhapatnam', area: 'Kancharapalem');
  return store;
}

void _report(String where, String what, bool ok) {
  // ignore: avoid_print
  print('VISIBLE $where | $what | ${ok ? 'YES' : 'NO'}');
}

void main() {
  for (final android in [false, true]) {
    final where = android ? 'android-app' : 'website';
    testWidgets('admin data shows in the $where', (tester) async {
      debugAndroidApp = android;
      addTearDown(() => debugAndroidApp = null);
      tester.view.physicalSize = android ? const Size(390, 2400) : const Size(1440, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store();
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      bool has(String text) => find.textContaining(text, findRichText: true).evaluate().isNotEmpty;
      final checks = {
        'Business Profile tagline': has('NIGHT TAGLINE'),
        'Business Profile header contact': has('NIGHT CONTACT 99999'),
        'Scrolling Text text': has('NIGHT SCROLLING TEXT'),
        'greeting with area (Hello, Kancharapalem People)': has('Hello, Kancharapalem People'),
        'location box shows the area name': find.text('Kancharapalem').evaluate().isNotEmpty,
        "banner Today's Kancharapalem Offers": has("Today's Kancharapalem Offers"),
        'offer of a shop within the km (promotions.radiusShopId)': has('NIGHT NEAR OFFER'),
        'offer without a shop is hidden': !has('NIGHT GENERAL OFFER'),
        'product of a shop within the km': has('NIGHT Rice'),
        'product of a far shop is hidden': !has('FAR Dal'),
      };
      for (final MapEntry(key: what, value: ok) in checks.entries) {
        _report(where, what, ok);
      }
      // Far away: the admin's "no offers" message with the area name.
      await store.setLocation('', '', lat: 28.61, lng: 77.21, town: 'New Delhi', area: 'Connaught Place');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      _report(where, 'Business Profile noOffersMessage ({town} = area)', has('NIGHT no offers near Connaught Place'));
      _report(where, 'nothing of far shops when far away', !has('NIGHT NEAR OFFER') && !has('NIGHT Rice'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }
}
