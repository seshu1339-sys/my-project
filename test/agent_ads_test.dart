// Ads by command, part 4 (owner spec D, I, 17 Nov 2026): who sees an admin ad (km, town, district, state, All India), the one rotation
// with the vendors (no priority), the form filled from the words with PREVIEW -> OK, and All India asking for YES. No server.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/admin_ads.dart';
import 'package:ecommerce_app/domain/agent_command.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/today_offers.dart';
import 'package:ecommerce_app/modules/offerstore/offerstore_module.dart';
import 'package:ecommerce_app/services/agent_log.dart';
import 'package:ecommerce_app/services/server_clock.dart';
import 'package:ecommerce_app/ui/agent_ad_flow.dart';
import 'package:ecommerce_app/ui/home_today_offers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 11, 17, 6);
  AdminAd ad(String id, {AdReach reach = AdReach.radius, String town = '', String district = '', String state = '', AdminAdPlacement placement = AdminAdPlacement.todaysOffers}) => AdminAd(
    id: id,
    title: 'Sale $id',
    photoUrl: 'https://x/$id.webp',
    placement: placement,
    reach: reach,
    latitude: 17.6676,
    longitude: 82.6129,
    radiusKm: 10,
    town: town,
    district: district,
    state: state,
    startsAt: now.subtract(const Duration(hours: 1)),
    endsAt: now.add(const Duration(days: 2)),
  );

  test('who sees it: within the km, the town, the district, the state, or all of India', () {
    expect(adminAdReaches(ad('a'), lat: 17.70, lng: 82.61), isTrue, reason: 'about 4 km');
    expect(adminAdReaches(ad('a'), lat: 17.90, lng: 82.61), isFalse, reason: 'about 26 km');
    expect(adminAdReaches(ad('a')), isFalse, reason: 'no place known: not for km ads');
    expect(adminAdReaches(ad('t', reach: AdReach.town, town: 'Narsipatnam'), town: 'narsipatnam'), isTrue);
    expect(adminAdReaches(ad('d', reach: AdReach.district, district: 'Anakapalli'), district: 'Anakapalli', town: 'Tuni'), isTrue);
    expect(adminAdReaches(ad('s', reach: AdReach.state, state: 'Andhra Pradesh'), state: 'Telangana'), isFalse);
    expect(adminAdReaches(ad('i', reach: AdReach.allIndia)), isTrue);
    final list = adminAdsFor([ad('b'), ad('a', placement: AdminAdPlacement.rightBox), ad('c', placement: AdminAdPlacement.both)], AdminAdPlacement.todaysOffers, now, lat: 17.67, lng: 82.61);
    expect([for (final a in list) a.id], ['b', 'c']);
    expect(ad('x').liveAt(now.add(const Duration(days: 3))), isFalse, reason: 'ended');
  });

  test('one queue with the vendors: an admin ad is neither always first nor always last', () {
    final firsts = <String>{};
    for (var i = 0; i < 30; i++) {
      final q = mixQueue<String>(['v1-$i', 'v2-$i', 'v3-$i'], ['admin-$i'], (s) => s);
      expect(q, hasLength(4));
      firsts.add(q.first.startsWith('admin') ? 'admin' : 'vendor');
    }
    expect(firsts, {'admin', 'vendor'});
  });

  test('the words fill the ad; what is missing is said', () {
    final c = parseAgentCommand("this photo, Today's Offers, Narsipatnam, 10 km, 2 days", places: const ['Narsipatnam']);
    final draft = adminAdFromCommand(c, now: now, photoUrl: 'https://x/p.webp');
    expect([draft.placement, draft.reach, draft.radiusKm, draft.town, draft.endsAt], [AdminAdPlacement.todaysOffers, AdReach.radius, 10.0, 'Narsipatnam', now.add(const Duration(days: 2))]);
    expect(draft.missing, contains('place'), reason: 'the point of the town is found by the form');
    expect(draft.copyWith(latitude: 17.6, longitude: 82.6).missing, isEmpty);
    expect(adminAdFromCommand(parseAgentCommand('show the live rate of tomato in Narsipatnam', places: const ['Narsipatnam']), now: now).missing, contains('item'));
  });

  group('screens', () {
    late Store store;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = Store();
      await store.init();
      AgentLog.testSink = [];
    });
    tearDown(() {
      AgentLog.testSink = null;
      store.dispose();
    });

    testWidgets('the form from the words: PREVIEW, then OK makes it live and logs it', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final saved = <AdminAd>[];
      final c = parseAgentCommand("this photo, Today's Offers, Narsipatnam, 10 km, 2 days", places: const ['Narsipatnam']);
      await tester.pumpWidget(MaterialApp(home: AgentAdFormPage(
        store: store,
        draft: adminAdFromCommand(c, now: DateTime.now(), photoUrl: 'https://x/p.webp'),
        command: c.text,
        resolve: (t) async => (lat: 17.6676, lng: 82.6129, district: 'Anakapalli', state: 'Andhra Pradesh'),
        save: (a) async { saved.add(a); return 'ad1'; },
      )));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('agent-ad-place'))).controller!.text, 'Narsipatnam');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('agent-ad-km'))).controller!.text, '10');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('agent-ad-days'))).controller!.text, '2');
      await tester.tap(find.byKey(const ValueKey('agent-ad-preview-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-ad-preview')), findsOneWidget);
      expect(find.textContaining('Narsipatnam · 10 km'), findsOneWidget);
      expect(saved, isEmpty, reason: 'nothing goes live before OK');
      await tester.tap(find.byKey(const ValueKey('agent-ad-ok')));
      await tester.pumpAndSettle();
      expect(saved.single.latitude, 17.6676);
      expect(find.byKey(const ValueKey('agent-ad-note')), findsOneWidget);
      expect(AgentLog.testSink!.last['action'], 'ad_live');
    });

    testWidgets('All India asks for YES first', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final saved = <AdminAd>[];
      final c = parseAgentCommand("Today's Offers ad All India 1 day");
      await tester.pumpWidget(MaterialApp(home: AgentAdFormPage(store: store, draft: adminAdFromCommand(c, now: DateTime.now(), photoUrl: 'https://x/p.webp'), save: (a) async { saved.add(a); return 'x'; })));
      await tester.tap(find.byKey(const ValueKey('agent-ad-preview-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agent-ad-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-risky-confirm')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
    });

    testWidgets("an admin ad in reach takes its turn in Today's Offers", (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ServerClock.debugReset);
      final base = DateTime.now().millisecondsSinceEpoch ~/ 30000 * 30000;
      ServerClock.debugSet(device: () => DateTime.fromMillisecondsSinceEpoch(base));
      store.latitude = 17.667;
      store.longitude = 82.611;
      store.catalog['promotions'] = [
        for (var i = 1; i <= 6; i++) Entry('box$i', {'placement': 'carousel', 'order': i, 'name': 'Promotion', 'backgroundColor': todayOfferDefaultColors[i - 1]}),
      ];
      final t = DateTime.fromMillisecondsSinceEpoch(base);
      final live = AdminAd(id: 'cmd1', title: 'Diwali sale', photoUrl: '', reach: AdReach.radius, latitude: 17.6676, longitude: 82.6129, radiusKm: 10, startsAt: t.subtract(const Duration(hours: 1)), endsAt: t.add(const Duration(days: 1)));
      final far = AdminAd(id: 'cmd2', title: 'Far', reach: AdReach.town, town: 'Hyderabad', startsAt: t.subtract(const Duration(hours: 1)), endsAt: t.add(const Duration(days: 1)));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TodayOffersSection(
        store: store,
        boxes: store.entries('promotions'),
        appearance: const Entry('promo', {'visibleCount': 6, 'animationMs': 3000}),
        vendorOffers: Stream.value(const <TodaysOffer>[]),
        adminAds: Stream.value([live, far]),
        seconds: 5,
      ))));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('admin-ad-box-cmd1')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-ad-box-cmd2')), findsNothing, reason: 'another town');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
