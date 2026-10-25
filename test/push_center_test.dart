import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_push_center.dart';

class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    if (name == 'pushNotOpened') return {'total': 1, 'people': [{'uid': 'u2', 'email': 'kiran@example.com', 'name': ''}]};
    return {'recipients': 2, 'sent': 2, 'noToken': 0, 'off': 0};
  }
}

void main() {
  testWidgets('the push centre: the audience, sending to a town, the automatic switches, and who did not open', (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _RecordingStore();
    store.catalog['settings'] = [const Entry('business', {'orderStatusNotificationsEnabled': false})];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PushCenterView(
          store: store,
          audience: () async => {'on': 3, 'off': 1, 'towns': [{'town': 'Narsipatnam', 'count': 2}, {'town': 'Tuni', 'count': 1}]},
          history: Stream.value(const [Entry('n1', {'title': 'Diwali offers', 'audience': 'all', 'recipients': 3, 'sent': 2, 'opened': 1, 'noToken': 1})]),
          typeDays: Stream.value(const [Entry('priceDrop~2026-10-25', {'type': 'priceDrop', 'day': '2026-10-25', 'sent': 5, 'opened': 2})]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('3 people have notifications on • 1 turned them off'), findsOneWidget);

    // the automatic switches: on unless switched off
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('push-auto-priceDrop'))).value, isTrue);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('push-auto-orderStatus'))).value, isFalse);
    expect(find.textContaining('Last 30 days: sent to 5 devices • opened 2'), findsOneWidget);

    // a sent one: got it, opened, no device; who did not open
    expect(find.textContaining('Got it: 2 of 3 • opened: 1 • no device: 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('push-not-opened-n1')));
    await tester.pumpAndSettle();
    expect(find.text('Not opened: 1'), findsOneWidget);
    expect(find.text('kiran@example.com'), findsOneWidget, reason: 'the email stands for the name when there is none');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // send to one town
    await tester.tap(find.text('A town'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('push-town')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Narsipatnam (2)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('push-title')), 'Fresh mangoes');
    await tester.enterText(find.byKey(const ValueKey('push-body')), 'Now at your shops');
    await tester.tap(find.byKey(const ValueKey('push-send')));
    await tester.pumpAndSettle();
    expect(find.text('"Fresh mangoes" goes to everyone in Narsipatnam with notifications on now.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('push-send-confirm')));
    await tester.pumpAndSettle();
    expect(store.calls.last.$1, 'sendPushNotification');
    expect(store.calls.last.$2, {'title': 'Fresh mangoes', 'body': 'Now at your shops', 'audience': 'town', 'town': 'Narsipatnam'});
    expect(find.text('Sent to 2 of 2 people.'), findsOneWidget);
  });
}
