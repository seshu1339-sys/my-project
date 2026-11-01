// The Android app's own sizes: separate from the website's in both directions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/android_sizes.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/admin_android_home.dart';
import 'package:ecommerce_app/ui/android_layout.dart';
import 'package:ecommerce_app/ui/home_section_config.dart';

const _website = [
  Entry('section_notice', {'fontSize': 35, 'borderWidth': 8, 'padding': 20, 'text': 'kept'}),
  Entry('section_promo', {'height': 60, 'desktopScale': 1.5}),
  Entry('section_search', {'mobileScale': 1.5, 'height': 10, 'margin': 6, 'padding': 5, 'borderWidth': 8, 'fontSize': 10}),
];

double _n(List<Entry> settings, String section, String key) => sectionConfig(settings, section).number(key);

Future<Store> _store(List<Entry> settings) async {
  SharedPreferences.setMockInitialValues({'locationAsked': true});
  final store = Store();
  await store.init();
  store.catalog.putIfAbsent('settings', () => []);
  store.catalog['settings']!.addAll(settings);
  return store;
}

Future<void> _phone(WidgetTester tester, Store store, {Size size = const Size(360, 2400)}) async {
  debugAndroidApp = true;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MarketApp(store: store));
  await tester.pump();
  await tester.pump();
}

void main() {
  tearDown(() => debugAndroidApp = null);

  group('the sizes', () {
    test('with nothing saved the settings come back untouched', () {
      expect(identical(AndroidSizes.from(_website).applyTo(_website), _website), isTrue);
    });

    test('a saved size replaces the website size for the app; what is not saved follows the website; other fields stay', () {
      final s = androidSettings([..._website, const Entry(androidSizesId, {'notice__fontSize': 16})]);
      expect(_n(s, 'notice', 'fontSize'), 16);
      expect(_n(s, 'notice', 'borderWidth'), 8);
      expect(sectionConfig(s, 'notice').text('text'), 'kept');
    });

    test('once separate, a website size never reaches the app, even one set later', () {
      final s = androidSettings([..._website, const Entry('section_popular', {'margin': 3}), const Entry(androidSizesId, {'separate': 'true', 'notice__fontSize': 16})]);
      expect(_n(s, 'notice', 'borderWidth'), 0);
      expect(_n(s, 'popular', 'margin'), 0);
      expect(sectionConfig(s, 'notice').text('text'), 'kept', reason: 'only sizes are separate');
    });

    test('scale and columns cover every screen size of the record', () {
      final s = androidSettings(const [Entry(androidSizesId, {'promo__scale': 1.2, 'products__columns': 2})]);
      expect(_n(s, 'promo', 'mobileScale'), 1.2);
      expect(_n(s, 'promo', 'tabletScale'), 1.2);
      expect(_n(s, 'products', 'mobileColumns'), 2);
    });

    test('values out of range and rubbish are kept inside the limits', () {
      final s = AndroidSizes.from(const [Entry(androidSizesId, {'notice__fontSize': 500, 'notice__padding': 'x', 'bogus__height': 3})]);
      expect(s.value('notice', 'fontSize'), 40);
      expect(s.values.length, 1);
    });

    test('copy keeps the look: the phone scale, not the desktop one, and the search box as the top row has it', () {
      final copied = AndroidSizes.copiedFields(tightForAndroid(_website));
      expect(copied['separate'], 'true');
      expect(copied['search__scale'], 1.5);
      expect(copied['search__height'], 44);
      expect(copied['search__margin'], 0);
      expect(copied['search__padding'], 0);
      expect(copied['search__borderWidth'], 8);
      expect(copied.containsKey('promo__scale'), isFalse, reason: 'desktopScale is not the phone');
      expect(copied['notice__padding'], 4, reason: 'the cap the app already applies');
      expect(copied['page__padding'], 6);
      final after = androidSettings([..._website, Entry(androidSizesId, copied)]);
      final before = tightForAndroid(_website);
      for (final key in ['fontSize', 'borderWidth', 'padding', 'height', 'mobileScale']) {
        expect(_n(after, 'notice', key), _n(before, 'notice', key), reason: 'notice $key');
      }
      // The website's 60 is below the cards' smallest height, so they are 120 high either way.
      expect(_n(after, 'promo', 'height'), 120);
      expect(_n(after, 'promo', 'mobileScale'), _n(before, 'promo', 'mobileScale'));
    });

    test('the website padding cap really reaches the section records', () {
      final s = tightForAndroid(const [Entry('section_nearby', {'padding': 30, 'margin': 20}), Entry('section_search', {'padding': 30})]);
      expect(_n(s, 'nearby', 'padding'), 4);
      expect(_n(s, 'nearby', 'margin'), 2);
      expect(_n(s, 'search', 'padding'), 30, reason: 'not a capped part');
    });
  });

  group('in the app', () {
    testWidgets('the page edge, the ad box height, the banner, the search box and the cards follow the saved sizes', (tester) async {
      final store = await _store([
        Entry('rightAdBoxes', {'count': 3, for (var n = 1; n <= 3; n++) 'box${n}Image': 'https://example.invalid/$n.jpg'}),
        const Entry('section_search', {'mobileScale': 1.5, 'borderWidth': 8}),
      ]);
      await _phone(tester, store);
      final box = find.byKey(const ValueKey('responsive-search-box'));
      final bigSearch = tester.getSize(box).height;
      final edge = tester.getTopLeft(find.byKey(const ValueKey('android-ads'))).dx;
      expect(edge, 6);
      store.catalog['settings']!.add(const Entry(androidSizesId, {'page__padding': 14, 'ads__height': 90, 'search__scale': 1, 'search__height': 40, 'promo__height': 150}));
      store.notifyListeners();
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('android-ads'))).dx, 14);
      expect(tester.getSize(find.byKey(const ValueKey('android-ads'))).height, 90);
      expect(tester.getSize(box).height, 48, reason: 'the box keeps its smallest height');
      expect(tester.getSize(box).height, lessThan(bigSearch));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('Items in a row really fits 2 and 3 on a phone, without overflow', (tester) async {
      for (final columns in [2, 3]) {
        final store = await _store([Entry(androidSizesId, {'products__columns': columns})]);
        await _phone(tester, store);
        final titles = find.byKey(const ValueKey('android-part-popular'));
        expect(titles, findsOneWidget);
        final cards = find.descendant(of: titles, matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'HomeProductTile'));
        expect(cards.evaluate().length, greaterThan(1));
        final first = tester.getTopLeft(cards.at(0)), second = tester.getTopLeft(cards.at(1));
        expect(second.dy, first.dy, reason: '$columns in a row');
        expect(tester.getSize(cards.at(0)).width, lessThan(360 / columns));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        store.dispose();
      }
    });

    testWidgets('the website ignores every Android size', (tester) async {
      debugAndroidApp = false;
      tester.view.physicalSize = const Size(390, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final plain = await _store(const []);
      await tester.pumpWidget(MarketApp(store: plain));
      await tester.pump();
      final search = find.byKey(const ValueKey('responsive-search-box'));
      final before = tester.getRect(search);
      await tester.pumpWidget(const SizedBox());
      plain.dispose();
      final store = await _store(const [Entry(androidSizesId, {'separate': 'true', 'search__height': 110, 'search__scale': 1.5, 'page__padding': 24, 'products__columns': 3})]);
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      expect(tester.getRect(search), before);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });

  testWidgets('Settings > Android App: sizes save, blanks clear, and Copy separates the two', (tester) async {
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(_website);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAndroidHomePage(store: store))));
    await tester.pumpAndSettle();
    Future<void> reach(String key) async {
      await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }

    await reach('android-size-part-notice');
    await tester.tap(find.byKey(const ValueKey('android-size-part-notice')));
    await tester.pumpAndSettle();
    expect(find.text('Blank = website (35)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('android-size-notice-fontSize')), '18');
    await reach('save-android-sizes');
    await tester.tap(find.byKey(const ValueKey('save-android-sizes')));
    await tester.pumpAndSettle();
    expect(AndroidSizes.from(store.entries('settings')).value('notice', 'fontSize'), 18);
    expect(_n(store.entries('settings'), 'notice', 'fontSize'), 35, reason: 'the website record is not written');

    await tester.pump(const Duration(seconds: 5)); // the "Saved" message goes away
    await tester.pumpAndSettle();
    await reach('android-size-notice-fontSize');
    await tester.enterText(find.byKey(const ValueKey('android-size-notice-fontSize')), 'big');
    await reach('save-android-sizes');
    await tester.tap(find.byKey(const ValueKey('save-android-sizes')));
    await tester.pumpAndSettle();
    expect(find.textContaining('must be a number'), findsOneWidget);

    await reach('android-sizes-copy');
    await tester.tap(find.byKey(const ValueKey('android-sizes-copy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('android-sizes-copy-yes')));
    await tester.pumpAndSettle();
    final sizes = AndroidSizes.from(store.entries('settings'));
    expect(sizes.separate, isTrue);
    expect(sizes.value('notice', 'fontSize'), 35);
    expect(tester.widget<Text>(find.byKey(const ValueKey('android-sizes-state'))).data, contains('separate sizes'));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
