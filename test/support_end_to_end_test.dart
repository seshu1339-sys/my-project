// Part 5 safety check (17 Nov 2026), end to end in one app: the real shell around the app, the real AI Support box, the real problem
// recorder. A Google sign-in that fails on our side opens the box with "We understood the problem…" and sends it by itself; a wrong
// email code (OTP) twice opens the user-side steps; location off opens "Turn on location"; every case is recorded with its cause, side,
// option and a screenshot. Only the server calls are fakes.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/support_texts.dart';
import 'package:ecommerce_app/services/app_monitoring.dart';
import 'package:ecommerce_app/services/difficulty_watch.dart';
import 'package:ecommerce_app/services/screen_capture.dart';
import 'package:ecommerce_app/ui/ai_support_box.dart';
import 'package:ecommerce_app/ui/support_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Store store;
  late List<Map<String, dynamic>> tickets;
  late List<Map<String, Object?>> recorded;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = Store();
    await store.init();
    AppMonitoring.reset();
    DifficultyWatch.reset();
    SupportShellState.shown.clear();
    recorded = AppMonitoring.testSink = [];
    ScreenCapture.testCapture = () async => '/9j/SCREEN';
    AppMonitoring.start(app: 'vendor');
    tickets = [];
    SupportShell.boxBuilder = (context, store, c, close) => Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 700,
      child: AiSupportBox(store: store, supportCase: c, close: close, send: (d) async {
        tickets.add(d);
        return {'id': 't${tickets.length}', 'status': 'sent'};
      }),
    );
  });
  tearDown(() {
    SupportShell.boxBuilder = null;
    AppMonitoring.testSink = null;
    ScreenCapture.testCapture = null;
    AppMonitoring.reset();
    DifficultyWatch.reset();
    store.dispose();
  });

  Future<void> app(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => withSupportShell(context, child, store),
      navigatorObservers: [SupportNavigatorObserver.shared],
      home: Scaffold(appBar: AppBar(title: const Text('Vendor sign-in')), body: const Center(child: Text('Continue with Google'))),
    ));
  }

  Future<List<Map<String, Object?>>> sent() async {
    await Future<void>.delayed(Duration.zero);
    await AppMonitoring.flushNow();
    return [for (final b in recorded) ...(b['problems'] as List).cast<Map<String, Object?>>()];
  }

  testWidgets('Google sign-in fails on our side: recorded, the box says we understood and sends it by itself', (tester) async {
    await app(tester);
    AppMonitoring.fail('login', 'Google sign-in: internal-error', option: 'Continue with Google');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-support-box')), findsOneWidget);
    expect(find.text(supportOursMessage('en', 1)), findsOneWidget);
    expect(tickets.single['auto'], isTrue);
    expect(tickets.single['problemKind'], 'login');
    final cases = await tester.runAsync(sent);
    expect(cases!.single['cause'], 'sign_in_failed');
    expect(cases.single['side'], 'our');
    expect(cases.single['shot'], '/9j/SCREEN');
  });

  testWidgets('a wrong email code twice: the user-side steps; location off: "Turn on location"', (tester) async {
    await app(tester);
    AppMonitoring.callFailed('verifyEmailLoginCode', 'invalid-argument', 'Wrong code.');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-support-box')), findsNothing, reason: 'the first wrong code shows only the form message');
    AppMonitoring.callFailed('verifyEmailLoginCode', 'invalid-argument', 'Wrong code.');
    await tester.pumpAndSettle();
    expect(find.text('The code you typed is not correct.'), findsOneWidget);
    expect(tickets, isEmpty, reason: 'user side: sent only if they say No');
    await tester.tap(find.byKey(const ValueKey('ai-support-yes')));
    await tester.pumpAndSettle();
    AppMonitoring.fail('location', 'Location services are off (register)');
    await tester.pumpAndSettle();
    expect(find.text('Location (GPS) is off on your phone.'), findsOneWidget);
    final cases = await tester.runAsync(sent);
    expect([for (final c in cases!) c['cause']], containsAll(['wrong_code', 'location_off']));
  });

  testWidgets('a person who closes Google sign-in is not troubled; a crash is recorded without a box', (tester) async {
    await app(tester);
    AppMonitoring.fail('login', 'Google sign-in: popup-closed-by-user');
    AppMonitoring.report(StateError('boom'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-support-box')), findsNothing);
    final cases = await tester.runAsync(sent);
    expect(cases!.map((c) => c['cause']), containsAll(['google_closed', 'error']));
    await tester.pump(const Duration(seconds: 61)); // the usage count of an error waits up to a minute for the usage service
  });
}
