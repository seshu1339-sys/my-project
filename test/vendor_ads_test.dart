import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_ads.dart';
import 'package:ecommerce_app/ui/vendor_ads_page.dart';

final now = DateTime(2026, 10, 26, 10, 30);

Future<Store> _store({List<Entry> ads = const [], List<Entry> subs = const [], List<Entry> stats = const [], List<Entry> notices = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['ads'] = [...ads];
  store.catalog['adSubmissions'] = [...subs];
  store.catalog['adStats'] = [...stats];
  store.catalog['vendorNotices'] = [...notices];
  return store;
}

void _phone(WidgetTester tester, [Size size = const Size(1000, 3000)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('what the vendor is told about an ad', () {
    expect(vendorAdState(const Entry('a', {'endsAt': '2026-12-01T00:00:00'}), now), 'Live');
    expect(vendorAdState(const Entry('a', {'endsAt': '2026-10-01T00:00:00'}), now), 'Expired');
    expect(vendorAdState(const Entry('a', {'startsAt': '2026-11-01T00:00:00'}), now), 'Scheduled');
    expect(vendorAdState(const Entry('a', {'status': 'rejected'}), now), 'Rejected');
    expect(vendorAdState(const Entry('a', {'active': false}), now), 'Inactive');
    expect(daysRemainingText(const Entry('a', {'endsAt': '2026-11-05T10:30:00'}), now), '10 days left');
    expect(daysRemainingText(const Entry('a', {'endsAt': '2026-10-26T20:00:00'}), now), 'ends today');
    expect(daysRemainingText(const Entry('a', {'endsAt': '2026-10-20T10:30:00'}), now), 'ended 6 day(s) ago');
    expect(daysRemainingText(const Entry('a', {}), now), '');
  });

  group('My Ads', () {
    testWidgets('shows each ad with its state, days left and the live counts, and what is waiting for approval', (tester) async {
      _phone(tester);
      final store = await _store(
        ads: const [
          Entry('live1', {'vendorId': 'v1', 'title': 'Diwali sale', 'contentType': 'text', 'endsAt': '2026-11-05T10:30:00', 'summary': 'daily'}),
          Entry('other', {'vendorId': 'v2', 'title': 'Someone else', 'contentType': 'text'}),
        ],
        subs: const [
          Entry('s1', {'vendorId': 'v1', 'title': 'Brand new ad', 'status': 'pending', 'kind': 'new'}),
          Entry('s2', {'vendorId': 'v1', 'title': 'Change', 'status': 'pending', 'kind': 'change', 'adId': 'live1'}),
          Entry('s3', {'vendorId': 'v1', 'title': 'Blurry one', 'status': 'rejected', 'reason': 'The picture is blurry', 'kind': 'new'}),
        ],
        stats: const [Entry('live1', {'vendorId': 'v1', 'views': 120, 'unique': 80, 'taps': 9, 'seconds': 640})],
        notices: const [Entry('n1', {'vendorId': 'v1', 'title': 'Your ad is live', 'body': 'Diwali sale was approved.', 'createdAt': '2026-10-25'})],
      );
      await tester.pumpWidget(MaterialApp(home: VendorAdsPage(store: store, uid: 'v1', now: now)));
      await tester.pumpAndSettle();
      expect(find.text('Diwali sale'), findsWidgets);
      expect(find.text('Someone else'), findsNothing, reason: 'only my ads');
      expect(find.byKey(const ValueKey('my-ad-state-live1')), findsOneWidget);
      expect((tester.widget(find.byKey(const ValueKey('my-ad-state-live1'))) as Text).data, 'Live');
      expect((tester.widget(find.byKey(const ValueKey('my-ad-days-live1'))) as Text).data, '10 days left');
      final stats = find.descendant(of: find.byKey(const ValueKey('my-ad-stats-live1')), matching: find.byType(Text));
      expect([for (final t in tester.widgetList<Text>(stats)) t.data], ['Views: 120', 'People: 80', 'Taps: 9', 'Seconds on screen: 640']);
      expect(find.text('Pending approval'), findsOneWidget);
      expect(find.textContaining('the change to your live ad'), findsOneWidget);
      expect(find.text('Rejected: The picture is blurry'), findsOneWidget);
      expect(find.text('Your ad is live'), findsOneWidget);
      // a change is already waiting: the vendor cannot send another
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('my-ad-change-live1'))).onPressed, isNull);
      expect(find.text('Daily summary'), findsOneWidget);
    });

    testWidgets('choosing a summary tells the server', (tester) async {
      _phone(tester);
      final store = await _store(ads: const [Entry('live1', {'vendorId': 'v1', 'title': 'Diwali sale', 'contentType': 'text'})]);
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(home: VendorAdsPage(store: store, uid: 'v1', now: now, call: (name, data) async {
        calls.add('$name ${data['adId']} ${data['mode']}');
        return {};
      })));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('my-ad-summary-live1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekly summary').last);
      await tester.pumpAndSettle();
      expect(calls, ['setAdSummary live1 weekly']);
    });

    testWidgets('a new ad is sent for approval with its plan and length; an error from the server is shown', (tester) async {
      _phone(tester);
      final store = await _store();
      final sent = <Map<String, dynamic>>[];
      var fail = true;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: Center(child: FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => VendorAdEditor(store: store, uid: 'v1', call: (name, data) async {
        if (fail) throw Exception('Add a title.');
        sent.add({'name': name, ...data});
        return {'status': 'pending'};
      }))), child: const Text('open')))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('vad-title')), 'Fresh vegetables');
      await tester.pump();
      expect(find.byKey(const ValueKey('vad-preview')), findsOneWidget);
      expect(find.text('Fresh vegetables'), findsWidgets, reason: 'the preview shows it');
      await tester.ensureVisible(find.byKey(const ValueKey('vad-send')));
      await tester.tap(find.byKey(const ValueKey('vad-send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vad-error')), findsOneWidget);
      expect(find.textContaining('Add a title.'), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const ValueKey('vad-package')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Gold').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vad-days')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 week').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('vad-send')));
      await tester.tap(find.byKey(const ValueKey('vad-send')));
      await tester.pumpAndSettle();
      expect(sent.single['name'], 'submitVendorAd');
      expect(sent.single['title'], 'Fresh vegetables');
      expect(sent.single['package'], 'gold');
      expect(sent.single['durationDays'], 7);
      expect(sent.single['contentType'], 'text');
      expect(find.text('open'), findsOneWidget, reason: 'back on the list');
      expect(find.textContaining('goes live only after the administrator approves'), findsOneWidget);
    });
  });

  group('the admin approves by hand', () {
    final pending = const Entry('s1', {
      'vendorId': 'v1', 'title': 'Brand new ad', 'contentType': 'text', 'status': 'pending', 'kind': 'new', 'package': 'silver', 'durationDays': 30, 'shopName': 'Ramu Kirana', 'vendorCode': 'VN00001',
    });

    Future<void> show(WidgetTester tester, Store store, {required List<String> log}) async {
      _phone(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAdsPage(
        store: store,
        decide: (id, ok, why) async => log.add('decide $id $ok "$why"'),
        remove: (id, why) async => log.add('remove $id "$why"'),
      ))));
      await tester.pumpAndSettle();
    }

    testWidgets('a pending ad is listed, not live, with the shop; approve and reject (with a reason) reach the server', (tester) async {
      final log = <String>[];
      final store = await _store(subs: [pending]);
      await show(tester, store, log: log);
      expect(find.byKey(const ValueKey('ads-pending-title')), findsOneWidget);
      expect(find.textContaining('New ad — Ramu Kirana VN00001'), findsOneWidget);
      expect(find.textContaining('Pending approval (1)'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('approve-s1')));
      await tester.pumpAndSettle();
      expect(log, ['decide s1 true ""']);
      // reject needs a reason
      await tester.tap(find.byKey(const ValueKey('reject-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ad-reason-ok')));
      await tester.pumpAndSettle();
      expect(log.length, 1, reason: 'an empty reason is not accepted');
      await tester.tap(find.byKey(const ValueKey('ad-reason-cancel')));
      await tester.pumpAndSettle();
      expect(log.length, 1);
      await tester.tap(find.byKey(const ValueKey('reject-s1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ad-reason')), 'Blurry picture');
      await tester.tap(find.byKey(const ValueKey('ad-reason-ok')));
      await tester.pumpAndSettle();
      expect(log.last, 'decide s1 false "Blurry picture"');
    });

    testWidgets('a change shows the live ad next to the new one', (tester) async {
      final log = <String>[];
      final store = await _store(
        ads: const [Entry('live1', {'vendorId': 'v1', 'title': 'Old title', 'contentType': 'text', 'order': 1})],
        subs: const [Entry('s2', {'vendorId': 'v1', 'title': 'New title', 'contentType': 'text', 'status': 'pending', 'kind': 'change', 'adId': 'live1', 'package': 'normal', 'durationDays': 30, 'shopName': 'Ramu', 'vendorCode': 'VN1'})],
      );
      await show(tester, store, log: log);
      expect(find.text('Live now'), findsOneWidget);
      expect(find.text('Wants to change to'), findsOneWidget);
      expect(find.text('Old title'), findsWidgets);
      expect(find.text('New title'), findsWidgets);
    });

    testWidgets('the admin can remove a vendor ad at any time', (tester) async {
      final log = <String>[];
      final store = await _store(ads: const [Entry('live1', {'vendorId': 'v1', 'title': 'Diwali sale', 'contentType': 'text', 'order': 1}), Entry('mine', {'title': 'Admin ad', 'contentType': 'text', 'order': 2})]);
      await show(tester, store, log: log);
      await tester.tap(find.byKey(const ValueKey('ad-menu-mine')));
      await tester.pumpAndSettle();
      expect(find.text('Remove vendor ad…'), findsNothing, reason: 'only vendor ads');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ad-menu-live1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove vendor ad…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ad-reason')), 'Against the rules');
      await tester.tap(find.byKey(const ValueKey('ad-reason-ok')));
      await tester.pumpAndSettle();
      expect(log, ['remove live1 "Against the rules"']);
    });

    testWidgets('the Pending approval filter shows only what is waiting', (tester) async {
      final store = await _store(ads: const [Entry('live1', {'title': 'Admin ad', 'contentType': 'text', 'order': 1})], subs: [pending]);
      await show(tester, store, log: []);
      await tester.tap(find.byKey(const ValueKey('ad-filter-pending')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pending-s1')), findsOneWidget);
      expect(find.byKey(const ValueKey('ad-row-live1')), findsNothing);
    });
  });
}
