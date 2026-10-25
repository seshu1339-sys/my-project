import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_inactive_accounts.dart';

class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  final calls = <(String, Map<String, dynamic>)>[];
  final updates = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    return {'uid': data['uid']};
  }

  @override
  Future<void> updateFields(String collection, String id, Map<String, dynamic> changes, {Set<String> remove = const {}, Entry? fallback}) async =>
      updates.add({'collection': collection, 'id': id, ...changes});
}

void main() {
  testWidgets('inactive accounts: the list by days, disable and enable, deleting a customer only after typing DELETE, and the automatic switches that start off', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _RecordingStore();
    final asked = <int>[];
    final lastActive = DateTime(2026, 8, 1).millisecondsSinceEpoch;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InactiveAccountsView(
          store: store,
          load: (days) async {
            asked.add(days);
            return [
              {'uid': 'c1', 'email': 'ravi@example.com', 'kind': 'customer', 'lastActiveAt': lastActive, 'inactiveDays': 86, 'disabled': false},
              if (days <= 30) {'uid': 'v1', 'email': 'shop@example.com', 'kind': 'vendor', 'lastActiveAt': lastActive, 'inactiveDays': 40, 'disabled': true},
            ];
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(asked, [30]);
    expect(find.text('2 accounts not used for 30 days or more'), findsOneWidget);
    expect(find.textContaining('vendor • last active 1 Aug 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('inactive-delete-v1')), findsNothing, reason: 'a vendor is disabled, never deleted here');

    // both automatic switches start off
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('inactive-auto-disable'))).value, isFalse);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('inactive-auto-delete'))).value, isFalse);
    await tester.tap(find.byKey(const ValueKey('inactive-auto-disable')));
    await tester.pumpAndSettle();
    expect(store.updates.single, {'collection': 'settings', 'id': 'inactiveAccounts', 'autoDisable': true});

    // disable, then enable
    await tester.tap(find.byKey(const ValueKey('inactive-toggle-c1')));
    await tester.pumpAndSettle();
    expect(store.calls.last.$1, 'setAccountDisabled');
    expect(store.calls.last.$2, {'uid': 'c1', 'disabled': true});
    expect(find.textContaining('Disabled: ravi@example.com'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('inactive-toggle-v1')));
    await tester.pumpAndSettle();
    expect(store.calls.last.$1, 'setAccountDisabled');
    expect(store.calls.last.$2, {'uid': 'v1', 'disabled': false});

    // delete: nothing happens without typing DELETE
    await tester.tap(find.byKey(const ValueKey('inactive-delete-c1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('delete-confirm-c1')), 'delete');
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(store.calls.where((c) => c.$1 == 'deleteInactiveAccount'), isEmpty);
    await tester.tap(find.byKey(const ValueKey('inactive-delete-c1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('delete-confirm-c1')), 'DELETE');
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(store.calls.last.$1, 'deleteInactiveAccount');
    expect(store.calls.last.$2, {'uid': 'c1', 'confirm': 'DELETE'});
    expect(find.text('1 account not used for 30 days or more'), findsOneWidget);

    // another number of days loads again
    await tester.tap(find.text('90 days'));
    await tester.pumpAndSettle();
    expect(asked, [30, 90]);
    expect(find.text('1 account not used for 90 days or more'), findsOneWidget);
  });
}
