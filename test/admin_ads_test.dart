import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/ads_admin.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_ads.dart';

final now = DateTime(2026, 10, 26, 10, 30);

Entry ad(String id, [Map<String, dynamic> more = const {}]) => Entry(id, {'title': 'Ad $id', 'order': int.tryParse(id.replaceAll(RegExp(r'\D'), '')) ?? 0, ...more});

Future<Store> _store({List<Entry> ads = const [], List<Entry> promotions = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['ads'] = [...ads];
  store.catalog['promotions'] = [...promotions];
  store.catalog['shops'] = const [Entry('shop-a', {'name': 'Suma Fresh Mart', 'order': 1})];
  return store;
}

Future<void> _show(WidgetTester tester, Store store) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAdsPage(store: store))));
  await tester.pumpAndSettle();
}

void main() {
  group('rules', () {
    test('only the admin sees payment and contact details', () {
      final split = splitAdFields({'title': 'x', 'shopName': 'Suma', 'phone': '9', 'amount': 5000, 'paid': true, 'notes': 'n', 'contactPerson': 'R'});
      expect(split.public.keys.toSet(), {'title', 'shopName'});
      expect(split.private.keys.toSet(), {'phone', 'amount', 'paid', 'notes', 'contactPerson'});
    });

    test('search by title, shop name or vendor code; filter by status', () {
      final ads = [
        ad('1', {'shopName': 'Suma Fresh Mart', 'vendorCode': 'VN1001'}),
        ad('2', {'shopName': 'Ramu Kirana', 'vendorCode': 'VN1002', 'endsAt': '2026-10-01T00:00:00'}),
        ad('3', {'active': false}),
        ad('4', {'startsAt': '2026-12-01T00:00:00'}),
        ad('5', {'status': 'rejected'}),
        ad('6', {'status': 'pending'}),
      ];
      expect(filterAds(ads, now, query: 'suma').map((a) => a.id), ['1']);
      expect(filterAds(ads, now, query: 'vn1002').map((a) => a.id), ['2']);
      expect(filterAds(ads, now, status: 'expired').map((a) => a.id), ['2']);
      expect(filterAds(ads, now, status: 'live').map((a) => a.id), ['1']);
      expect(filterAds(ads, now, status: 'inactive').map((a) => a.id), ['3']);
      expect(filterAds(ads, now, status: 'scheduled').map((a) => a.id), ['4']);
      expect(filterAds(ads, now, status: 'rejected').map((a) => a.id), ['5']);
      expect(filterAds(ads, now, status: 'pending').map((a) => a.id), ['6']);
    });

    test('3-day expiry warning and renewal', () {
      final soon = ad('1', {'endsAt': '2026-10-28T12:00:00'});
      final later = ad('2', {'endsAt': '2026-12-28T12:00:00'});
      final done = ad('3', {'endsAt': '2026-10-01T12:00:00'});
      expect(adsEndingSoon([soon, later, done], now).map((a) => a.id), ['1']);
      expect(adDaysLeft(soon, now), 3);
      expect(adDaysLeft(done, now), 0);
      expect(renewedEnd(soon, now, by: 'week'), '2026-11-04T12:00:00.000');
      expect(renewedEnd(soon, now, by: 'month'), '2026-11-28T12:00:00.000');
      expect(renewedEnd(done, now, by: 'week'), '2026-11-02T10:30:00.000', reason: 'an expired ad starts again from now');
      expect(renewedEnd(ad('4', {'endsAt': '2026-01-31T00:00:00'}), DateTime(2026, 1, 20), by: 'month'), '2026-02-28T00:00:00.000');
    });

    test('a package fills rounds, seconds and the daily limit; a copy is switched off and goes to the end', () {
      expect(packageFill('gold'), {'package': 'gold', 'rounds': 3, 'seconds': 10, 'maxPerDay': 0});
      expect(packageFill('normal')['rounds'], 1);
      final copy = duplicateAd(ad('1', {'pinned': true, 'shopName': 'S'}), 'new', 9);
      expect(copy.id, 'new');
      expect(copy.text('title'), 'Ad 1 (copy)');
      expect(copy.active, isFalse);
      expect(copy.data['pinned'], false);
      expect(copy.number('order'), 9);
      expect(copy.text('shopName'), 'S');
    });

    test('old ad boxes are copied once, as unified ads, keeping what they showed', () {
      final promos = [
        const Entry('promo-big', {'placement': 'ad', 'name': 'Big Savings Everyday', 'description': 'Up to 50% OFF', 'target': 'shop:shop-a', 'active': true}),
        const Entry('promo-box', {'placement': 'box', 'name': 'A box'}),
        const Entry('promo-link', {'placement': 'ad', 'name': 'L', 'target': 'https://example.test', 'active': false}),
      ];
      expect(adsToImport(promos, const []).map((p) => p.id), ['promo-big', 'promo-link']);
      final a = adFromPromotion(promos.first, 1);
      expect(a.id, 'import-promo-big');
      expect(a.text('title'), 'Big Savings Everyday');
      expect(a.text('text'), 'Up to 50% OFF');
      expect(a.text('tapAction'), 'shop');
      expect(a.text('tapValue'), 'shop-a');
      expect(adFromPromotion(promos.last, 2).active, isFalse);
      expect(adsToImport(promos, [a]).map((p) => p.id), ['promo-link'], reason: 'already imported');
    });
  });

  group('screens', () {
    testWidgets('the Ads section: one serial number, each ad a sub-number, search and filters', (tester) async {
      final store = await _store(ads: [
        ad('1', {'shopName': 'Suma Fresh Mart', 'vendorCode': 'VN1001'}),
        ad('2', {'shopName': 'Ramu Kirana', 'vendorCode': 'VN1002', 'active': false}),
      ]);
      await _show(tester, store);
      expect(find.textContaining('Ads  ·  23'), findsWidgets);
      expect(find.text('23.1'), findsOneWidget);
      expect(find.text('23.2'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('ad-search')), 'VN1002');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ad-row-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('ad-row-1')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('ad-search')), '');
      await tester.tap(find.byKey(const ValueKey('ad-filter-inactive')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ad-row-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('ad-row-1')), findsNothing);
    });

    testWidgets('switch off, duplicate, renew and delete (after a confirmation)', (tester) async {
      final store = await _store(ads: [ad('1', {'endsAt': '2026-10-28T12:00:00', 'active': true})]);
      await _show(tester, store);
      await tester.tap(find.byKey(const ValueKey('ad-active-1')));
      await tester.pumpAndSettle();
      expect(store.entries('ads').single.active, isFalse);
      await tester.tap(find.byKey(const ValueKey('ad-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(store.entries('ads').length, 2);
      expect(store.entries('ads').any((a) => a.text('title') == 'Ad 1 (copy)'), isTrue);
      await tester.tap(find.byKey(const ValueKey('ad-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renew +1 month'));
      await tester.pumpAndSettle();
      expect(store.entries('ads').firstWhere((a) => a.id == '1').text('endsAt'), startsWith('2026-'));
      expect(store.entries('ads').firstWhere((a) => a.id == '1').active, isTrue);
      // delete: Cancel keeps it, Delete removes it
      await tester.tap(find.byKey(const ValueKey('ad-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ad-delete-cancel')));
      await tester.pumpAndSettle();
      expect(store.entries('ads').length, 2);
      await tester.tap(find.byKey(const ValueKey('ad-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ad-delete-confirm')));
      await tester.pumpAndSettle();
      expect(store.entries('ads').any((a) => a.id == '1'), isFalse);
    });

    testWidgets('an ad ending within 3 days is flagged, with a renew button', (tester) async {
      final soon = DateTime.now().add(const Duration(days: 2)).toIso8601String();
      final store = await _store(ads: [ad('1', {'endsAt': soon})]);
      await _show(tester, store);
      expect(find.byKey(const ValueKey('ads-expiring')), findsOneWidget);
      await tester.tap(find.text('+1 week'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ads-expiring')), findsNothing);
    });

    testWidgets('the old ad boxes can be copied into the list once', (tester) async {
      final store = await _store(promotions: const [Entry('promo-big', {'placement': 'ad', 'name': 'Big Savings Everyday', 'description': 'Up to 50% OFF', 'active': true})]);
      await _show(tester, store);
      await tester.tap(find.byKey(const ValueKey('ad-import')));
      await tester.pumpAndSettle();
      expect(store.entries('ads').single.id, 'import-promo-big');
      expect(store.entries('promotions').length, 1, reason: 'the old record stays');
      expect(find.byKey(const ValueKey('ad-import')), findsNothing);
    });

    testWidgets('common settings show their current value and change it on save', (tester) async {
      final store = await _store();
      await _show(tester, store);
      await tester.tap(find.byKey(const ValueKey('ads-common-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Ad boxes on a computer screen (3)'), findsOneWidget);
      expect(find.text('Corner radius (12px)'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('ads-config-desktopSlots-null')), '4');
      await tester.ensureVisible(find.byKey(const ValueKey('ads-config-save')));
      await tester.tap(find.byKey(const ValueKey('ads-config-save')));
      await tester.pumpAndSettle();
      expect(AdsConfig.from(store.entries('settings')).desktopSlots, 4);
      expect(find.text('Ad boxes on a computer screen (4)'), findsOneWidget);
    });

    testWidgets('Add Ad: four groups, a package fills the numbers, public and private details are saved apart', (tester) async {
      final store = await _store();
      await _show(tester, store);
      await tester.tap(find.byKey(const ValueKey('ad-add')));
      await tester.pumpAndSettle();
      for (final g in const ['content', 'when', 'howmuch', 'shop']) {
        expect(find.byKey(ValueKey('ad-group-$g')), findsOneWidget);
      }
      await tester.tap(find.text('Text only'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ad-field-title')), 'Diwali sale');
      await tester.enterText(find.byKey(const ValueKey('ad-field-shopName')), 'Suma Fresh Mart');
      await tester.enterText(find.byKey(const ValueKey('ad-field-vendorCode')), 'VN1001');
      await tester.enterText(find.byKey(const ValueKey('ad-field-phone')), '9876543210');
      await tester.enterText(find.byKey(const ValueKey('ad-field-amount')), '1500');
      await tester.ensureVisible(find.byKey(const ValueKey('ad-package-normal')));
      await tester.tap(find.byKey(const ValueKey('ad-package-normal')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gold').last);
      await tester.pumpAndSettle();
      expect((tester.widget(find.byKey(const ValueKey('ad-field-seconds'))) as TextField).controller!.text, '10');
      await tester.ensureVisible(find.byKey(const ValueKey('ad-day-6')));
      await tester.tap(find.byKey(const ValueKey('ad-day-6')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ad-day-7')));
      await tester.tap(find.byKey(const ValueKey('ad-paid')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('ad-save')));
      await tester.tap(find.byKey(const ValueKey('ad-save')));
      await tester.pumpAndSettle();
      final saved = store.entries('ads').single;
      expect(saved.text('title'), 'Diwali sale');
      expect(saved.text('package'), 'gold');
      expect(saved.number('rounds'), 3);
      expect(saved.text('days'), '1,2,3,4,5');
      expect(saved.text('shopName'), 'Suma Fresh Mart');
      expect(saved.data.containsKey('phone'), isFalse, reason: 'contact details are not in the public record');
      expect(saved.data.containsKey('amount'), isFalse);
      final private = store.entries('adsPrivate').single;
      expect(private.id, saved.id);
      expect(private.text('phone'), '9876543210');
      expect(private.text('amount'), '1500');
      expect(private.data['paid'], true);
    });

    testWidgets('the list and the editor fit a phone screen', (tester) async {
      final store = await _store(ads: [ad('1', {'shopName': 'Suma Fresh Mart', 'endsAt': '2026-12-28T12:00:00'})]);
      tester.view.physicalSize = const Size(390, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAdsPage(store: store))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('ad-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ad-save')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bad ad is refused with a reason', (tester) async {
      final store = await _store();
      await _show(tester, store);
      await tester.tap(find.byKey(const ValueKey('ad-add')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('ad-save')));
      await tester.tap(find.byKey(const ValueKey('ad-save')));
      await tester.pumpAndSettle();
      expect(find.text('Add a title or a picture.'), findsOneWidget);
      expect(store.entries('ads'), isEmpty);
    });
  });
}
