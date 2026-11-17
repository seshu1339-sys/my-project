// NIGHT CHECK (11 Nov 2026): what happens when the admin turns options off, leaves them blank or deletes the records: the customer
// website and Android app must not crash, and an option switched off must really hide its part. Prints EMPTY / OFF lines for
// NIGHT_CHECK_REPORT.md. Does not change any app code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/android_layout.dart';

Future<Store> _store(Map<String, List<Entry>> catalog, {bool located = true}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog = catalog;
  if (located) await store.setLocation('530008', '', lat: 17.734, lng: 83.279, town: 'Visakhapatnam', area: 'Kancharapalem');
  return store;
}

Future<Object?> _open(WidgetTester tester, Store store, {required bool android}) async {
  debugAndroidApp = android;
  tester.view.physicalSize = android ? const Size(390, 2000) : const Size(1440, 2200);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MarketApp(store: store));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return tester.takeException();
}

void main() {
  tearDown(() => debugAndroidApp = null);
  const shop = Entry('kpl', {'name': 'Kancharapalem Kirana', 'latitude': 17.735, 'longitude': 83.280});
  const product = Entry('p', {'name': 'NIGHT Rice', 'price': 40, 'compareAtPrice': 55, 'shopId': 'kpl', 'stock': 9});

  for (final android in [false, true]) {
    final where = android ? 'android-app' : 'website';
    testWidgets('$where: every record deleted, blank values, odd values: no crash', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cases = <String, Map<String, List<Entry>>>{
        'everything deleted (empty database)': {},
        'business deleted, catalogue present': {'shops': [shop], 'products': [product]},
        'blank business values': {
          'settings': [const Entry('business', {'name': '', 'tagline': '', 'radiusKm': '', 'enabledLanguages': '', 'deliveryFeeTiers': '', 'headerContact': ''})],
          'shops': [shop], 'products': [product],
        },
        'odd values (text in number fields, negative km)': {
          'settings': [const Entry('business', {'radiusKm': 'abc', 'freeDeliveryAbove': 'x', 'vendorPhotoLimit': -3}), const Entry('theme', {'primary': 'not-a-colour', 'fontSize': 'big'})],
          'shops': [shop], 'products': [product],
        },
        'areaNames with broken rows': {'settings': [const Entry('areaNames', {'renames': '= x\nfoo =\n=', 'blocked': '\n,\n'})]},
      };
      for (final MapEntry(key: name, value: catalog) in cases.entries) {
        for (final located in [true, false]) {
          final store = await _store({for (final e in catalog.entries) e.key: [...e.value]}, located: located);
          final error = await _open(tester, store, android: android);
          // ignore: avoid_print
          print('EMPTY $where | $name | ${located ? 'place chosen' : 'no place'} | ${error == null ? 'no crash' : 'CRASH $error'}');
          expect(error, isNull, reason: '$where $name');
          await tester.pumpWidget(const SizedBox());
          store.dispose();
        }
      }
    });

    testWidgets('$where: options switched off really hide their part', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<bool> shows(List<Entry> settings, String text) async {
        final store = await _store({'settings': settings, 'shops': [shop], 'products': [product]});
        await _open(tester, store, android: android);
        final found = find.textContaining(text).evaluate().isNotEmpty;
        await tester.pumpWidget(const SizedBox());
        store.dispose();
        return found;
      }

      final on = await shows([const Entry('scrollingText', {'text': 'NIGHT TICKER', 'active': true})], 'NIGHT TICKER');
      final off = await shows([const Entry('scrollingText', {'text': 'NIGHT TICKER', 'active': false})], 'NIGHT TICKER');
      // ignore: avoid_print
      print('OFF $where | Scrolling Text active=false hides it | on=${on ? 'shown' : 'hidden'} off=${off ? 'SHOWN (bug)' : 'hidden'}');
      final noticeOn = await shows(const [], "Today's Kancharapalem Offers");
      final noticeOff = await shows([const Entry('section_notice', {'visible': false})], "Today's Kancharapalem Offers");
      // ignore: avoid_print
      print('OFF $where | Today\'s Offers banner visible=false hides it | on=${noticeOn ? 'shown' : 'hidden'} off=${noticeOff ? 'SHOWN (bug)' : 'hidden'}');
      expect(off, isFalse);
    });
  }
}
