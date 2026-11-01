// The Android app's home screen: one small top row, the ad boxes right under it, then the same rows as the website.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/android_layout.dart';

Future<Store> _store({int boxes = 4, Map<String, Object> androidHome = const {}, Map<String, Object> prefs = const {'locationAsked': true}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = Store();
  await store.init();
  store.catalog.putIfAbsent('settings', () => []);
  store.catalog['settings']!
    ..add(Entry('rightAdBoxes', {'count': boxes, for (var n = 1; n <= boxes; n++) 'box${n}Image': 'https://example.invalid/$n.jpg'}))
    ..add(const Entry('adsConfig', {'seconds': 3}))
    ..add(Entry('androidHome', androidHome));
  return store;
}

void main() {
  tearDown(() => debugAndroidApp = null);

  testWidgets('Android: one small top row, ads under it, no right-hand ad column, the website rows still there', (tester) async {
    debugAndroidApp = true;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.byKey(const ValueKey('android-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('android-location')), findsOneWidget);
    expect(find.byKey(const ValueKey('responsive-search-box')), findsOneWidget);
    expect(find.byTooltip('Voice search'), findsOneWidget);
    expect(find.byTooltip('Camera search'), findsOneWidget);
    expect(find.text('Welcome'), findsNothing);
    expect(find.byKey(const ValueKey('right-ad-boxes')), findsNothing);
    // the top row, then the ads straight under it
    final header = tester.getRect(find.byKey(const ValueKey('android-header')));
    final ads = tester.getRect(find.byKey(const ValueKey('android-ads')));
    expect(header.height, lessThan(64));
    // (the test store is not live, so its one-line "Demo marketplace" notice sits between them)
    expect(ads.top, lessThan(header.bottom + 60));
    // two whole boxes of one size side by side
    final a = tester.getRect(find.byKey(const ValueKey('android-ad-1'))), b = tester.getRect(find.byKey(const ValueKey('android-ad-2')));
    expect(a.width, closeTo(b.width, .5));
    expect(a.top, b.top);
    expect(b.right, lessThanOrEqualTo(360));
    expect(find.byKey(const ValueKey('android-ad-3')).hitTestable(), findsNothing);
    // they slide on by themselves after the admin's "seconds" (3 here): box 3 comes in, one box at a time
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getRect(find.byKey(const ValueKey('android-ad-2'))).left, closeTo(a.left, 1));
    expect(find.byKey(const ValueKey('android-ad-3')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Android: the settings icon opens a menu with notifications, wishlist, bag, account, seller, office and the languages', (tester) async {
    debugAndroidApp = true;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(boxes: 0);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('android-settings-menu')));
    await tester.pumpAndSettle();
    for (final t in ['Notifications', 'Wishlist', 'Shopping bag', 'Your account', 'Become a Seller', 'Office / Head Office']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing saved yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the website is not the Android layout: the usual header and the right-hand ad boxes', (tester) async {
    debugAndroidApp = false;
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.byKey(const ValueKey('android-header')), findsNothing);
    expect(find.byKey(const ValueKey('android-ads')), findsNothing);
    expect(find.byKey(const ValueKey('right-ad-boxes')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  Future<void> open(WidgetTester tester, Store store) async {
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Android: "Where are you shopping?" comes only the first time the app opens, never again', (tester) async {
    debugAndroidApp = true;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var store = await _store(prefs: {});
    await open(tester, store);
    expect(find.text('Where are you shopping?'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // dismiss without choosing
    await tester.pumpAndSettle();
    expect(find.text('Where are you shopping?'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    // the app is opened again: no dialog
    store = Store();
    await store.init();
    await open(tester, store);
    expect(find.text('Where are you shopping?'), findsNothing);
    // only the pin opens it
    await tester.tap(find.byKey(const ValueKey('android-location')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Where are you shopping?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Android: a saved location opens the home page straight away, with no dialog even the first time', (tester) async {
    debugAndroidApp = true;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(prefs: {'pincode': '531116', 'address': 'Narsipatnam', 'town': 'Narsipatnam'});
    await open(tester, store);
    expect(find.text('Where are you shopping?'), findsNothing);
    expect(find.text('Narsipatnam'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the website never opens the location dialog by itself', (tester) async {
    debugAndroidApp = false;
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(prefs: {});
    await open(tester, store);
    expect(find.text('Where are you shopping?'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Android: with no ads the row shows empty boxes; one ad fills one box; the switch hides the row', (tester) async {
    Future<Store> show(int boxes, {Map<String, Object> androidHome = const {}}) async {
      final store = await _store(boxes: boxes, androidHome: androidHome);
      debugAndroidApp = true;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      return store;
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final empty0 = find.byKey(const ValueKey('android-ad-empty-0')), empty1 = find.byKey(const ValueKey('android-ad-empty-1'));

    var store = await show(0);
    expect(find.byKey(const ValueKey('android-ads')), findsOneWidget);
    expect(tester.getSize(empty0), tester.getSize(empty1));
    expect(tester.getTopRight(empty1).dx, lessThanOrEqualTo(360));
    await tester.pumpWidget(const SizedBox());
    store.dispose();

    store = await show(1);
    expect(find.byKey(const ValueKey('android-ad-1')), findsOneWidget);
    expect(empty0, findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('android-ad-1'))), tester.getSize(empty1));
    await tester.pumpWidget(const SizedBox());
    store.dispose();

    store = await show(0, androidHome: {'showAds': 'false'});
    expect(find.byKey(const ValueKey('android-ads')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  Future<void> androidApp(WidgetTester tester, Store store) async {
    debugAndroidApp = true;
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    await tester.pump();
  }

  double top(WidgetTester tester, String part) => tester.getTopLeft(find.byKey(ValueKey('android-part-$part'))).dy;

  testWidgets('Android: nothing saved means every part is built in the usual order', (tester) async {
    final store = await _store();
    await androidApp(tester, store);
    final parts = ['ads', 'scrollingText', 'notice', 'quickFresh', 'promo', 'strip', 'popular', 'localServices', 'nearby'];
    for (final p in parts) {
      expect(find.byKey(ValueKey('android-part-$p')), findsOneWidget, reason: p);
    }
    for (var i = 1; i < parts.length; i++) {
      expect(top(tester, parts[i]), greaterThanOrEqualTo(top(tester, parts[i - 1])), reason: '${parts[i - 1]} before ${parts[i]}');
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Android: the saved order and the hidden parts are used, and a later change applies without a restart', (tester) async {
    final store = await _store(androidHome: {'order': 'nearby,promo', 'hidden': 'scrollingText,popular,localServices'});
    await androidApp(tester, store);
    expect(find.byKey(const ValueKey('android-part-scrollingText')), findsNothing);
    expect(find.byKey(const ValueKey('android-part-popular')), findsNothing);
    expect(find.byKey(const ValueKey('android-part-localServices')), findsNothing);
    expect(top(tester, 'nearby'), lessThan(top(tester, 'promo')));
    expect(top(tester, 'promo'), lessThan(top(tester, 'ads')));
    expect(find.byKey(const ValueKey('android-part-notice')), findsOneWidget);
    store.catalog['settings']!.removeWhere((e) => e.id == 'androidHome');
    store.catalog['settings']!.add(const Entry('androidHome', {'order': 'promo', 'hidden': 'nearby', 'showAds': 'false'}));
    store.notifyListeners();
    await tester.pump();
    expect(find.byKey(const ValueKey('android-part-nearby')), findsNothing);
    expect(find.byKey(const ValueKey('android-part-ads')), findsNothing);
    expect(find.byKey(const ValueKey('android-part-scrollingText')), findsOneWidget);
    expect(top(tester, 'promo'), lessThan(top(tester, 'scrollingText')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the website ignores the Android order and hidden parts', (tester) async {
    debugAndroidApp = false;
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(androidHome: {'order': 'nearby', 'hidden': 'promo,popular,notice', 'showAds': 'false'});
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.byKey(const ValueKey('today-offers')), findsOneWidget);
    expect(find.byKey(const ValueKey('right-ad-boxes')), findsOneWidget);
    expect(find.byKey(const ValueKey('android-part-promo')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
