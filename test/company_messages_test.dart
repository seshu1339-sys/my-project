import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/modules/companymessages/company_inbox.dart';
import 'package:ecommerce_app/modules/companymessages/company_messages_data.dart';
import 'package:ecommerce_app/modules/companymessages/compose_page.dart';

// Company messages (cost cuts part 5, 18 Nov 2026): the vendor's bell and inbox (badge, type, date and time, edited, payment box), the
// admin's compose page and log, and the staff limits on the page.
CompanyMessage msg(String id, Map<String, dynamic> d) => CompanyMessage.from(id, d);

void main() {
  final now = DateTime.utc(2026, 11, 18, 6);

  test('the vendor sees everyone\'s messages that fit their town and category, and their own; newest first; not past "show until"', () {
    final everyone = [
      msg('all', {'all': true, 'title': 'For all', 'sentAt': DateTime.utc(2026, 11, 10)}),
      msg('town', {'towns': ['narsipatnam'], 'title': 'Town', 'sentAt': DateTime.utc(2026, 11, 12)}),
      msg('pair', {'towns': ['narsipatnam'], 'categories': ['grocery'], 'title': 'Pair', 'sentAt': DateTime.utc(2026, 11, 13)}),
      msg('other', {'towns': ['narsipatnam'], 'categories': ['clothes'], 'title': 'Other category'}),
      msg('tuni', {'towns': ['tuni'], 'title': 'Other town'}),
      msg('old', {'all': true, 'showUntil': '2026-11-17', 'title': 'Ended'}),
    ];
    final mine = [msg('direct', {'public': false, 'title': 'Your login was reset', 'sentAt': DateTime.utc(2026, 11, 14)})];
    final inbox = vendorInbox(everyone: everyone, mine: mine, town: 'Krishna Bazar (Narsipatnam)', category: 'Grocery', now: now);
    expect(inbox.map((m) => m.id), ['direct', 'pair', 'town', 'all']);
  });

  test('push topics are the same names the server uses', () {
    expect(companyTopicsFor(uid: 'u1', town: 'Krishna Bazar (Narsipatnam)', category: 'Fancy Store'),
        ['cm_vendors_all', 'cm_vendors_t_narsipatnam', 'cm_vendors_c_fancy-store', 'cm_vendor_u1']);
    expect(companyTopicsFor(uid: 'u1'), ['cm_vendors_all', 'cm_vendor_u1']);
  });

  testWidgets('the bell shows the unread count; the inbox shows the badge, type, time, "edited" and the payment box; opening counts reads', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await tester.runAsync(store.init);
    final data = CompanyInboxData(
      messages: [
        msg('p1', {'type': 'payment', 'title': 'New Silver price', 'body': 'From December', 'oldAmount': 499, 'newAmount': 549, 'startsOn': '2026-12-01', 'edited': true, 'sentAt': DateTime.utc(2026, 11, 18, 4, 30)}),
        msg('g1', {'type': 'general', 'title': 'Market closed', 'body': 'Sunday', 'sentAt': DateTime.utc(2026, 11, 17)}),
      ],
      read: {'g1'},
    );
    final marked = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(appBar: AppBar(actions: [CompanyBell(store: store, load: () async => data, markRead: (ids) async => marked.add(ids))])),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget, reason: 'one unread');
    await tester.tap(find.byKey(const ValueKey('company-bell')));
    await tester.pumpAndSettle();
    expect(find.text('Messages from LOCAMARKET'), findsOneWidget);
    expect(find.byKey(const ValueKey('company-badge')), findsNWidgets(2), reason: 'the official badge on every message');
    expect(find.text('Payment / charges change'), findsOneWidget);
    expect(find.byKey(const ValueKey('company-edited')), findsOneWidget);
    expect(find.text('18/11/2026 10:00'), findsOneWidget, reason: 'Indian time');
    expect(find.text('Old amount: ₹499  →  New amount: ₹549\nStarts on: 01/12/2026'), findsOneWidget);
    expect(marked, [['p1']], reason: 'only the unread one is counted');
  });

  group('the compose page', () {
    late Store store;
    late List<(String, Map<String, dynamic>)> calls;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = Store();
      await store.init();
      store.catalog['shops'] = [
        const Entry('v1', {'name': 'Lakshmi', 'town': 'Krishna Bazar (Narsipatnam)', 'category': 'Grocery', 'vendorCode': 'VEN-1'}),
        const Entry('v2', {'name': 'Ravi', 'town': 'Tuni', 'category': 'Clothes', 'vendorCode': 'VEN-2'}),
      ];
      calls = [];
    });

    Future<void> pump(WidgetTester tester, {bool staff = false, List<CompanyMessage> log = const []}) async {
      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CompanyComposePage(
            store: store,
            staff: staff,
            loadLog: () async => log,
            call: (name, data) async {
              calls.add((name, data));
              return name == 'previewCompanyMessage' ? {'count': 7} : {'meantFor': 7, 'id': 'm1', 'staff': const []};
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('town + category together, the count before sending, then Send', (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const ValueKey('cm-title')), 'Diwali');
      await tester.enterText(find.byKey(const ValueKey('cm-body')), 'Free offer box');
      await tester.tap(find.text('Town / category'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cm-town-narsipatnam')));
      await tester.tap(find.byKey(const ValueKey('cm-cat-grocery')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cm-preview')));
      await tester.pumpAndSettle();
      expect(find.text('This will go to 7 vendors.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cm-send')));
      await tester.pumpAndSettle();
      final (name, data) = calls.last;
      expect(name, 'sendCompanyMessage');
      expect(data['type'], 'general');
      expect(data['target'], {'towns': ['narsipatnam'], 'categories': ['grocery']});
      expect(find.text('Sent to 7 vendors.'), findsOneWidget);
    });

    testWidgets('several Vendor IDs at once; Payment / charges carries the old and new amount', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('cm-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Payment / charges change').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('cm-title')), 'New fee');
      await tester.enterText(find.byKey(const ValueKey('cm-body')), 'Silver changes');
      await tester.enterText(find.byKey(const ValueKey('cm-old')), '499');
      await tester.enterText(find.byKey(const ValueKey('cm-new')), '549');
      await tester.tap(find.text('Vendor IDs'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('cm-codes')), 'ven-1, VEN-2');
      await tester.tap(find.byKey(const ValueKey('cm-send')));
      await tester.pumpAndSettle();
      final data = calls.last.$2;
      expect(data['type'], 'payment');
      expect([data['oldAmount'], data['newAmount']], [499, 549]);
      expect(data['target'], {'vendorCodes': ['VEN-1', 'VEN-2']});
    });

    testWidgets('staff: no Payment / charges type and no sender list', (tester) async {
      await pump(tester, staff: true);
      await tester.tap(find.byKey(const ValueKey('cm-type')));
      await tester.pumpAndSettle();
      expect(find.text('Payment / charges change'), findsNothing);
      expect(find.byKey(const ValueKey('cm-senders')), findsNothing);
      expect(find.text('All my vendors'), findsWidgets);
    });

    testWidgets('the log: who, when, to whom, for how many, read by how many; old words after an edit; deleted stays', (tester) async {
      await pump(tester, log: [
        msg('m1', {
          'type': 'offer', 'title': 'Diwali', 'body': 'b', 'sentAt': DateTime.utc(2026, 11, 18, 4, 30), 'meantFor': 12, 'readCount': 5, 'pushes': 1,
          'target': {'towns': ['narsipatnam'], 'categories': ['grocery']}, 'sentBy': {'role': 'staff', 'code': 'STF-9'}, 'edited': true,
          'versions': [{'title': 'Old Diwali', 'body': 'old words', 'replacedBy': 'STF-9'}],
        }),
        msg('m2', {'type': 'general', 'title': 'Gone', 'body': 'b', 'deleted': true, 'target': {'all': true}, 'sentBy': {'role': 'admin', 'code': 'owner'}}),
      ]);
      expect(find.text('For 12 vendors · read by 5 · 1 push'), findsOneWidget);
      expect(find.textContaining('by staff STF-9 · to Town: narsipatnam + Category: grocery'), findsOneWidget);
      expect(find.text('Earlier words (1)'), findsOneWidget);
      expect(find.text('Deleted'), findsOneWidget);
      expect(find.byKey(const ValueKey('cm-edit-m2')), findsNothing, reason: 'a deleted message cannot be changed');
      await tester.tap(find.byKey(const ValueKey('cm-delete-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cm-delete-yes')));
      await tester.pumpAndSettle();
      expect(calls.last.$1, 'deleteCompanyMessage');
      expect(calls.last.$2, {'id': 'm1'});
    });
  });
}
