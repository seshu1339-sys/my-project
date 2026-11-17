// AI Agent + Health System, part 4 (17 Nov 2026): the admin AI Agent opens with a summary (most affected first, people, times, phones,
// reports waiting, the fix agent's state), each issue with its Telugu reason and proposed fix, "Fix this?" Fix / Don't fix (with what to
// do next), the exact changes of a ready fix with the tests and AI cost, OK only after a confirm, "It did not work" and Undo. No server.
import 'dart:async';

import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/fix_texts.dart';
import 'package:ecommerce_app/domain/health_status.dart';
import 'package:ecommerce_app/ui/fix_agent_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Store store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = Store();
    await store.init();
  });
  tearDown(() => store.dispose());

  final problems = [
    AppProblem(id: 'p-few', app: 'customer', platform: 'web', kind: 'api', message: 'placeOrder: internal', screen: 'cart', option: 'Place order', count: 30, users: 2, cause: 'server_error'),
    AppProblem(id: 'p-many', app: 'vendor', platform: 'android', kind: 'tap', message: 'No answer to "Save item" after 3 taps', screen: 'add_item', option: 'Save item', count: 9, users: 6, side: 'device', cause: 'no_response', devices: const {'Xiaomi Redmi 9': 8, 'Redmi 10': 1}),
  ];

  Future<(StreamController<List<Map<String, dynamic>>>, List<Map<String, dynamic>>, List<(String, Map<String, dynamic>)>)> pump(WidgetTester tester, {DateTime? seen}) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final requests = StreamController<List<Map<String, dynamic>>>.broadcast();
    addTearDown(requests.close);
    final asked = <Map<String, dynamic>>[];
    final decided = <(String, Map<String, dynamic>)>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FixAgentPage(
          store: store,
          data: FixAgentData(
            problems: () async => mostAffectedFirst(problems),
            waitingByProblem: () async => {'p-many': 3},
            requests: () => requests.stream,
            agentSeen: () => Stream.value(seen),
            ask: (r) async => asked.add(r),
            decide: (id, c) async => decided.add((id, c)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (requests, asked, decided);
  }

  testWidgets('the summary first, the most affected issue first, the facts, the Telugu reason and the fix', (tester) async {
    await pump(tester, seen: DateTime.now().subtract(const Duration(minutes: 5)));
    expect(find.text('2 open problems · 8 people affected · 3 reports waiting for a reply'), findsOneWidget);
    expect(find.textContaining('Fix agent on the PC is running'), findsOneWidget);
    final many = tester.getTopLeft(find.byKey(const ValueKey('fix-issue-p-many'))).dy;
    final few = tester.getTopLeft(find.byKey(const ValueKey('fix-issue-p-few'))).dy;
    expect(many, lessThan(few), reason: '6 people before 2 people with more errors');
    expect(find.textContaining('6 people, 9 times'), findsOneWidget);
    expect(find.textContaining('phones: Xiaomi Redmi 9 ×8'), findsOneWidget);
    expect(find.textContaining('3 reports waiting for a reply'), findsWidgets);
    expect(find.text('కారణం: ${fixTextOf(side: 'device', cause: 'no_response').reason}'), findsOneWidget);
  });

  testWidgets('Fix sends a request with the problem; Don\'t fix asks what to do next and the agent gets the instruction', (tester) async {
    final (_, asked, _) = await pump(tester);
    expect(find.textContaining('Fix agent on the PC is not running'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fix-yes-p-many')));
    await tester.pumpAndSettle();
    expect(asked.single['problemId'], 'p-many');
    expect(asked.single['users'], 6);
    expect(asked.single['proposedFix'], isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('fix-dont-p-few')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('fix-instruction-p:p-few')), 'Only show a clear message, do not change the order code');
    await tester.tap(find.byKey(const ValueKey('fix-instruction-send-p:p-few')));
    await tester.pumpAndSettle();
    expect(asked.last['instruction'], 'Only show a clear message, do not change the order code');
  });

  testWidgets('a ready fix shows the exact changes, tests and AI cost; OK only after the confirm', (tester) async {
    final (requests, _, decided) = await pump(tester);
    requests.add([
      {'id': 'r1', 'problemId': 'p-many', 'status': 'ready', 'fixKind': 'app', 'summary': 'The Save item button now shows a spinner and saves once.', 'tests': '1101 passed', 'files': ['lib/ui/add_item.dart'], 'diff': '--- a/lib/ui/add_item.dart\n+++ b/lib/ui/add_item.dart\n+  saving = true;', 'cost': 'Claude Code on this PC'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text(fixStatusNames['ready']!), findsOneWidget);
    expect(find.textContaining('Android app code'), findsOneWidget);
    expect(find.text('Tests: 1101 passed'), findsOneWidget);
    expect(find.text('AI cost of this fix: Claude Code on this PC'), findsOneWidget);
    await tester.tap(find.text('The exact changes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('saving = true;'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fix-ok-r1')));
    await tester.pumpAndSettle();
    expect(decided, isEmpty, reason: 'nothing before the confirm');
    await tester.tap(find.byKey(const ValueKey('fix-ok-confirm')));
    await tester.pumpAndSettle();
    expect(decided.single.$1, 'r1');
    expect(decided.single.$2['status'], 'approved');
  });

  testWidgets('a live fix: Undo after a confirm; "It did not work" sends the next instruction', (tester) async {
    final (requests, _, decided) = await pump(tester);
    requests.add([{'id': 'r2', 'problemId': 'p-few', 'status': 'live', 'fixKind': 'server', 'commit': 'abc1234', 'approvedBy': 'admin1'}]);
    await tester.pumpAndSettle();
    expect(find.text('Live'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fix-undo-r2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fix-undo-confirm')));
    await tester.pumpAndSettle();
    expect(decided.last.$2['status'], 'undoRequested');
    await tester.tap(find.byKey(const ValueKey('fix-didnt-work-r2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('fix-instruction-r:r2')), 'Orders still fail for COD; check the stock step');
    await tester.tap(find.byKey(const ValueKey('fix-instruction-send-r:r2')));
    await tester.pumpAndSettle();
    expect(decided.last.$2, {'status': 'requested', 'instruction': 'Orders still fail for COD; check the stock step'});
  });

  test('every our-side cause has a Telugu reason and a proposed fix; every fix kind says how it goes live', () {
    for (final cause in ['server_error', 'server_refused', 'server_down', 'server_slow', 'sign_in_failed', 'upload_failed', 'no_response', 'hang', 'stuck_loading', 'slow', 'repeat_fail', 'crash', 'error']) {
      final t = fixTextOf(side: 'our', cause: cause);
      expect(t.reason, isNotEmpty, reason: cause);
      expect(t.fix, isNotEmpty, reason: cause);
    }
    for (final k in FixKind.values) {
      expect(fixKindNames[k], isNotEmpty);
    }
    expect(fixKindOf('server'), FixKind.server);
  });
}
