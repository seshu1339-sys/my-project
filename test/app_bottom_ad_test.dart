import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/right_boxes.dart';
import 'package:ecommerce_app/services/ad_tracker.dart';
import 'package:ecommerce_app/ui/admin_ads.dart';
import 'package:ecommerce_app/ui/app_bottom_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final now = DateTime(2026, 11, 3, 10);

Entry ad(String id, Map<String, Object> extra) => Entry(id, {'title': id, 'contentType': 'text', 'order': 1, ...extra});

Future<Store> store(List<Entry> ads) async {
  SharedPreferences.setMockInitialValues({});
  final s = Store();
  await s.init();
  s.catalog['ads'] = [...ads];
  s.catalog['shops'] = const [Entry('v1', {'name': 'Ramu Kirana', 'category': 'Grocery '}), Entry('v2', {'name': 'Vijaya Dairy', 'category': 'Dairy'})];
  return s;
}

void main() {
  test('an ad with no audience is for customers only, as every ad made before audiences', () {
    expect(adAudience(ad('a', {})), {'customers'});
    expect(adAudience(ad('a', {'audience': 'vendors,staff'})), {'vendors', 'staff'});
    expect(adAudience(ad('a', {'audience': 'nobody'})), {'customers'});
    expect([for (final a in customerAds([ad('c', {}), ad('v', {'audience': 'vendors'}), ad('cv', {'audience': 'customers,vendors'})])) a.id], ['c', 'cv']);
  });

  test('vendor ads reach every vendor, or only the chosen shop categories (any spelling case); staff ads reach staff', () {
    final ads = [
      ad('all-vendors', {'audience': 'vendors'}),
      ad('grocery', {'audience': 'vendors', 'categories': 'grocery, Bakery'}),
      ad('staff', {'audience': 'staff', 'categories': 'Grocery'}),
      ad('customers', {}),
      ad('ended', {'audience': 'vendors', 'endsAt': '2026-11-01T00:00:00'}),
    ];
    expect([for (final a in appAds(ads, now, shopCategory: ' Grocery ')) a.id], ['all-vendors', 'grocery']);
    expect([for (final a in appAds(ads, now, shopCategory: 'Dairy')) a.id], ['all-vendors']);
    expect([for (final a in appAds(ads, now, staff: true)) a.id], ['staff']);
  });

  test('the admin switch for vendors seeing their views is on unless turned off', () {
    expect(AdsConfig.from(const []).vendorSeesViews, isTrue);
    expect(AdsConfig.from(const [Entry('adsConfig', {'vendorSeesViews': 'false'})]).vendorSeesViews, isFalse);
  });

  testWidgets('the vendor app box shows the ad for the vendor\'s category and counts a view after a second on screen', (tester) async {
    final s = await store([ad('grocery', {'audience': 'vendors', 'categories': 'Grocery', 'seconds': 5})]);
    final sent = <Map<String, Object?>>[];
    final tracker = AdsTracker(visitorId: 'device-0123456789abcdef', platform: 'android', transport: (b) async => sent.add(b), flushEvery: const Duration(milliseconds: 1));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: AppBottomAd(store: s, uid: 'v1', tracker: tracker, now: () => now)))));
    expect(find.byKey(const ValueKey('app-bottom-ad-grocery')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 10));
    expect([for (final b in sent) for (final e in b['events'] as List) (e as Map)['type']], contains('view'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a vendor of another category, or no live ad, sees the "your ad here" box', (tester) async {
    final s = await store([ad('grocery', {'audience': 'vendors', 'categories': 'Grocery'})]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppBottomAd(store: s, uid: 'v2', now: () => now))));
    expect(find.byKey(const ValueKey('app-bottom-ad-empty')), findsOneWidget);
    expect(find.text(rightBoxPlaceholder), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the staff app box takes turns between the staff ads, each for its seconds', (tester) async {
    final s = await store([ad('s1', {'audience': 'staff', 'seconds': 3, 'order': 1}), ad('s2', {'audience': 'staff', 'seconds': 3, 'order': 2}), ad('v', {'audience': 'vendors'})]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppBottomAd(store: s, staff: true, now: () => now))));
    expect(find.byKey(const ValueKey('app-bottom-ad-s1')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('app-bottom-ad-s2')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-bottom-ad-v')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the box is under every page only once signed in', (tester) async {
    final s = await store([]);
    await tester.pumpWidget(MaterialApp(builder: (context, child) => withAppBottomAd(context, child, s), home: const Scaffold(body: Text('page'))));
    expect(find.byKey(const ValueKey('app-bottom-ad')), findsNothing, reason: 'nobody is signed in');
  });

  testWidgets('the admin aims an ad at vendors of one shop category, picked from the categories the shops have', (tester) async {
    final s = await store([]);
    s.catalog['promotions'] = [];
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAdsPage(store: s))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ad-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text only'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ad-field-title')), 'Wholesale rice');
    expect(find.byKey(const ValueKey('ad-category-grocery')), findsNothing, reason: 'categories only for vendor ads');
    await tester.ensureVisible(find.byKey(const ValueKey('ad-audience-vendors')));
    await tester.tap(find.byKey(const ValueKey('ad-audience-vendors')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ad-audience-customers')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ad-category-dairy')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ad-category-grocery')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('ad-save')));
    await tester.tap(find.byKey(const ValueKey('ad-save')));
    await tester.pumpAndSettle();
    final saved = s.entries('ads').single;
    expect(saved.text('audience'), 'vendors');
    expect(saved.text('categories'), 'Grocery');
    expect(customerAds(s.entries('ads')), isEmpty);
    expect(appAds(s.entries('ads'), DateTime.now().add(const Duration(minutes: 1)), shopCategory: 'grocery'), hasLength(1));
  });
}
