// AI Agent + Health System, part 3 (17 Nov 2026): the AI Support box. A user-side problem shows "Your problem is", the steps and the
// one-tap fix, then "Did this solve it?" (Yes closes, No sends to the team); an our-side problem is sent by itself with "We understood
// the problem … within 1 day" (the admin's days); "Tell us more" adds to that report; a typed question gets the AI answer or, with AI
// off, goes to the team; the person's language; "My problem reports" with Sent / Seen / Solved and the team's reply. No server: seams.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/problem_cause.dart';
import 'package:ecommerce_app/domain/support_case.dart';
import 'package:ecommerce_app/domain/support_texts.dart';
import 'package:ecommerce_app/services/app_monitoring.dart';
import 'package:ecommerce_app/ui/ai_support_box.dart';
import 'package:ecommerce_app/ui/my_support_page.dart';
import 'package:ecommerce_app/ui/support_inbox_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const locationOff = SupportCase(kind: 'location', message: 'Location services are off (nearby)', cause: ProblemCause('user', 'location_off'), option: 'Near me', screen: 'home', fingerprint: 'location/1');
const serverBroke = SupportCase(kind: 'api', message: 'placeOrder: internal INTERNAL', cause: ProblemCause('our', 'server_error'), option: 'Place order', screen: 'cart', fingerprint: 'api/2');

void main() {
  late Store store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = Store();
    await store.init();
    AppMonitoring.reset();
    AppMonitoring.start(app: 'customer');
  });
  tearDown(() {
    AppMonitoring.reset();
    store.dispose();
  });

  Future<void> pumpBox(WidgetTester tester, SupportCase c, {required List<Map<String, dynamic>> sent, List<Map<String, dynamic>>? asked, String aiText = '', List<SupportFix>? fixes, void Function()? onClose}) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var n = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: AiSupportBox(
              store: store,
              supportCase: c,
              close: onClose ?? () {},
              send: (d) async {
                sent.add(d);
                return {'id': d['ticketId'] ?? 't${++n}', 'status': 'sent'};
              },
              ask: (d) async {
                asked?.add(d);
                return {'text': aiText};
              },
              pickScreenshot: () async => '/9j/PICKED',
              fix: (f) async => fixes?.add(f),
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('user side: the problem, Step 1-3 and the one-tap fix; Yes closes without sending', (tester) async {
    final sent = <Map<String, dynamic>>[];
    final fixes = <SupportFix>[];
    var closed = false;
    await pumpBox(tester, locationOff, sent: sent, fixes: fixes, onClose: () => closed = true);
    expect(find.text('AI Support'), findsOneWidget);
    expect(find.text('Location (GPS) is off on your phone.'), findsOneWidget);
    expect(find.text('Step 1: Tap "Turn on location".'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-support-fix')));
    expect(fixes, [SupportFix.locationSettings]);
    expect(sent, isEmpty, reason: 'a user-side problem is not sent unless they say No');
    await tester.tap(find.byKey(const ValueKey('ai-support-yes')));
    expect(closed, isTrue);
  });

  testWidgets('user side, No: it goes to the team and the status shows Sent', (tester) async {
    final sent = <Map<String, dynamic>>[];
    await pumpBox(tester, locationOff, sent: sent);
    await tester.tap(find.byKey(const ValueKey('ai-support-no')));
    await tester.pumpAndSettle();
    expect(sent.single['auto'], isFalse);
    expect(sent.single['cause'], 'location_off');
    expect(sent.single['side'], 'user');
    expect(find.byKey(const ValueKey('ai-support-status')), findsOneWidget);
  });

  testWidgets('our side: sent by itself, no technical words, the admin\'s days; Tell us more adds to it with a screenshot', (tester) async {
    store.catalog['settings'] = [...store.entries('settings'), const Entry('support', {'replyDays': 2})];
    final sent = <Map<String, dynamic>>[];
    await pumpBox(tester, serverBroke, sent: sent);
    expect(sent.single['auto'], isTrue, reason: 'sent to the admin by itself');
    expect(sent.single['option'], 'Place order');
    expect(find.text(supportOursMessage('en', 2)), findsOneWidget);
    expect(find.textContaining('INTERNAL'), findsNothing, reason: 'no technical details for the person');
    await tester.enterText(find.byKey(const ValueKey('ai-support-more')), 'I pressed it twice');
    await tester.tap(find.byKey(const ValueKey('ai-support-shot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-support-send')));
    await tester.pumpAndSettle();
    expect(sent[1]['ticketId'], 't1', reason: 'added to the report already sent');
    expect(sent[1]['text'], 'I pressed it twice');
    expect(sent[1]['screenshot'], '/9j/PICKED');
  });

  testWidgets('a typed question: the AI answer when AI is on; with AI off it goes to the team', (tester) async {
    final sent = <Map<String, dynamic>>[];
    final asked = <Map<String, dynamic>>[];
    await pumpBox(tester, locationOff, sent: sent, asked: asked, aiText: '1. Open Settings.');
    await tester.enterText(find.byKey(const ValueKey('ai-support-question')), 'Why no shops near me?');
    await tester.tap(find.byKey(const ValueKey('ai-support-ask')));
    await tester.pumpAndSettle();
    expect(find.text('1. Open Settings.'), findsOneWidget);
    expect(asked.single['context'], containsPair('cause', 'location_off'));
    expect(sent, isEmpty);
    await pumpBox(tester, locationOff, sent: sent, asked: asked);
    await tester.enterText(find.byKey(const ValueKey('ai-support-question')), 'Why no shops near me?');
    await tester.tap(find.byKey(const ValueKey('ai-support-ask')));
    await tester.pumpAndSettle();
    expect(find.text(supportWord('aiOff', 'en')), findsOneWidget);
    expect(sent.single['text'], 'Why no shops near me?');
  });

  testWidgets('in the person\'s language: Telugu', (tester) async {
    store.language = 'te';
    await pumpBox(tester, serverBroke, sent: []);
    expect(find.text('AI సహాయం'), findsOneWidget);
    expect(find.text(supportOursMessage('te', 1)), findsOneWidget);
  });

  test('every user-side cause has written help in English, Telugu and Hindi; others fall back to English', () {
    for (final cause in userCauses.where((c) => c != 'google_closed')) {
      for (final lang in supportLanguages) {
        final h = supportHelp(cause, lang);
        expect(h, isNotNull, reason: '$cause/$lang');
        expect(h!.steps.length, greaterThanOrEqualTo(3));
      }
    }
    expect(supportHelp('offline', 'ta')!.problem, supportHelp('offline', 'en')!.problem);
    expect(supportOursMessage('en', 1), contains('within 1 day'));
    expect(supportOursMessage('en', 3), contains('within 3 days'));
  });

  testWidgets('My problem reports: status and the team\'s reply; a new reply is noticed once', (tester) async {
    SharedPreferences.setMockInitialValues({MySupportPage.hasTicketsKey: true});
    final list = [
      {'id': 'a', 'status': 'solved', 'text': 'Order button', 'reply': 'Fixed, please try again.', 'at': 1000, 'replyAt': 5000},
      {'id': 'b', 'status': 'sent', 'text': 'Photo', 'reply': '', 'at': 2000, 'replyAt': 0},
    ];
    expect(await MySupportPage.hasNewReply(store, load: () async => list), isTrue);
    await tester.pumpWidget(MaterialApp(home: MySupportPage(store: store, load: () async => list)));
    await tester.pumpAndSettle();
    expect(find.text('Solved'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('LocaMarket team: Fixed, please try again.'), findsOneWidget);
    expect(await MySupportPage.hasNewReply(store, load: () async => list), isFalse, reason: 'seen now');
  });

  testWidgets('the admin reads the reports (waiting first), replies, marks Seen / Solved, or the whole problem solved', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final answers = <String>[];
    final solved = <String>[];
    final tickets = [
      {'id': 'w1', 'status': 'sent', 'app': 'vendor', 'platform': 'android', 'side': 'our', 'message': 'saveQuickItem: internal', 'text': 'Save does not work', 'option': 'Save item', 'phone': '9000000001', 'userCode': 'VEN-1', 'problemId': 'vendor~android~api~x', 'lang': 'te'},
      {'id': 's1', 'status': 'solved', 'app': 'customer', 'platform': 'web', 'side': 'user', 'message': 'offline', 'text': ''},
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SupportInboxPage(
      store: store,
      load: () async => tickets,
      answer: (id, status, reply) async => answers.add('$id:$status:$reply'),
      solveProblem: (p) async => solved.add(p),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('AI Support reports: 1 waiting for a reply'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-ticket-w1')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-ticket-s1')), findsNothing, reason: 'Open shows the ones not solved');
    expect(find.textContaining('📞 9000000001'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('support-reply-w1')), 'We fixed it, please try again.');
    await tester.tap(find.byKey(const ValueKey('support-solved-w1')));
    await tester.pumpAndSettle();
    expect(answers.single, 'w1:solved:We fixed it, please try again.');
    await tester.tap(find.byKey(const ValueKey('support-solve-problem-w1')));
    await tester.pumpAndSettle();
    expect(solved.single, 'vendor~android~api~x');
  });
}
