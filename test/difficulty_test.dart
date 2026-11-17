// AI Agent + Health System, part 2 (17 Nov 2026): every case gets its cause (USER / OUR side), the option, network, Android version
// and an automatic screenshot with the text fields covered; the same save failing again is a "repeat" case; three taps on the same
// option with no answer, a hang and a screen stuck loading are cases too; the option is highlighted. No server: seams.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/problem_cause.dart';
import 'package:ecommerce_app/domain/support_case.dart';
import 'package:ecommerce_app/services/app_monitoring.dart';
import 'package:ecommerce_app/services/difficulty_watch.dart';
import 'package:ecommerce_app/services/screen_capture.dart';
import 'package:ecommerce_app/ui/support_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const online = DeviceState(network: 'wifi');

void main() {
  group('the cause', () {
    test('a failed server call: user side when the person can fix it, else our side', () {
      expect(causeOfCall('placeOrder', 'unavailable', '', const DeviceState(network: 'none')).toString(), 'user/offline');
      expect(causeOfCall('placeOrder', 'unauthenticated', '', online).toString(), 'user/session_expired');
      expect(causeOfCall('saveQuickItem', 'invalid-argument', 'Enter the price.', online).toString(), 'user/missing_field');
      expect(causeOfCall('verifyEmailLoginCode', 'invalid-argument', 'Wrong code.', online).toString(), 'user/wrong_code');
      expect(causeOfCall('verifyEmailLoginCode', 'deadline-exceeded', 'This code has expired. Ask for a new one.', online).toString(), 'user/code_expired');
      expect(causeOfCall('requestEmailLoginCode', 'resource-exhausted', 'Please wait 30s', online).toString(), 'user/too_many_tries');
      expect(causeOfCall('approveVendor', 'permission-denied', 'Sign in again.', online).toString(), 'user/session_expired');
      expect(causeOfCall('approveVendor', 'permission-denied', 'Missing or insufficient permissions.', online).toString(), 'our/server_refused');
      expect(causeOfCall('placeOrder', 'internal', 'INTERNAL', online).toString(), 'our/server_error');
      expect(causeOfCall('placeOrder', 'unavailable', '', const DeviceState(network: 'mobile', slowInternet: true)).toString(), 'user/slow_internet');
      expect(causeOfCall('placeOrder', 'unavailable', '', online).toString(), 'our/server_down');
    });

    test('a key failure: location, photos, sign-in, taps, hangs, loading', () {
      expect(causeOf('location', 'Location services are off (nearby)', online).toString(), 'user/location_off');
      expect(causeOf('location', 'Location permission denied (nearby)', online).toString(), 'user/location_denied');
      expect(causeOf('upload', 'Photo upload (items): unauthorized', online).toString(), 'user/session_expired');
      expect(causeOf('upload', 'Photo upload (items): object too large', online).toString(), 'user/photo_too_big');
      expect(causeOf('upload', 'Photo upload (items): unknown', online).toString(), 'our/upload_failed');
      expect(causeOf('login', 'Google sign-in: popup-closed-by-user', online).toString(), 'user/google_closed');
      expect(causeOf('login', 'Google sign-in: network-request-failed', online).toString(), 'user/offline');
      expect(causeOf('login', 'Google sign-in: internal-error', online).toString(), 'our/sign_in_failed');
      expect(causeOf('email', 'Verification email: too-many-requests', online).toString(), 'user/too_many_tries');
      expect(causeOf('tap', 'No answer to "Save"', online).toString(), 'our/no_response');
      expect(causeOf('freeze', 'App did not answer', online).toString(), 'our/hang');
      expect(causeOf('stuck', 'Still loading', online).toString(), 'our/stuck_loading');
      expect(causeOf('stuck', 'Still loading', const DeviceState(network: 'mobile', slowInternet: true)).toString(), 'user/slow_internet');
      expect(causeOf('api', 'x', const DeviceState(network: 'none')).toString(), 'user/offline');
      expect(causeOf('crash', 'x', const DeviceState(network: 'none')).toString(), 'our/crash', reason: 'a crash is ours even offline');
    });

    test('the AI Support box: our side and fixable user causes; a missing field or wrong code only the second time', () {
      expect(opensSupportBox('api', const ProblemCause('our', 'server_error'), times: 1), isTrue);
      expect(opensSupportBox('location', const ProblemCause('user', 'location_off'), times: 1), isTrue);
      expect(opensSupportBox('api', const ProblemCause('user', 'missing_field'), times: 1), isFalse);
      expect(opensSupportBox('api', const ProblemCause('user', 'missing_field'), times: 2), isTrue);
      expect(opensSupportBox('otp', const ProblemCause('user', 'wrong_code'), times: 2), isTrue);
      expect(opensSupportBox('login', const ProblemCause('user', 'google_closed'), times: 3), isFalse, reason: 'the person closed it');
      expect(opensSupportBox('error', const ProblemCause('our', 'error'), times: 5), isFalse, reason: 'an error the person may not have seen');
      expect(opensSupportBox('slow', const ProblemCause('our', 'slow'), times: 1), isFalse);
    });

    test('taps repeated on purpose are never "no answer"', () {
      for (final l in ['+', '-', '2', 'Add', 'Next', 'Remove one', 'Back']) {
        expect(isRepeatTapOption(l), isTrue, reason: l);
      }
      for (final l in ['Save item', 'Place order', 'Send me a code', 'ధృవీకరించండి']) {
        expect(isRepeatTapOption(l), isFalse, reason: l);
      }
    });
  });

  group('the record', () {
    late List<Map<String, Object?>> sent;
    late List<SupportCase> boxes;
    setUp(() {
      AppMonitoring.reset();
      DifficultyWatch.reset();
      sent = AppMonitoring.testSink = [];
      boxes = [];
      AppMonitoring.start(app: 'vendor');
      AppMonitoring.onSupportCase = boxes.add;
      ScreenCapture.testCapture = () async => '/9j/SHOT';
    });
    tearDown(() {
      AppMonitoring.testSink = null;
      ScreenCapture.testCapture = null;
      AppMonitoring.reset();
      DifficultyWatch.reset();
    });

    Future<List<Map<String, Object?>>> problems() async {
      await Future<void>.delayed(Duration.zero);
      await AppMonitoring.flushNow();
      return [for (final b in sent) ...(b['problems'] as List).cast<Map<String, Object?>>()];
    }

    test('a failed save: its cause, the option tapped just before, a screenshot; the AI Support box opens', () async {
      AppMonitoring.network = 'mobile';
      AppMonitoring.lastTap = (label: 'Save item', rect: const Rect.fromLTWH(10, 20, 100, 40), at: DateTime.now());
      AppMonitoring.screen = 'add_item';
      AppMonitoring.callFailed('saveQuickItem', 'internal', 'INTERNAL');
      final list = await problems();
      expect(list.single['kind'], 'api');
      expect(list.single['side'], 'our');
      expect(list.single['cause'], 'server_error');
      expect(list.single['option'], 'Save item');
      expect(list.single['screen'], 'add_item');
      expect(list.single['shot'], '/9j/SHOT');
      expect(sent.single['network'], 'mobile');
      expect(boxes.single.rect, const Rect.fromLTWH(10, 20, 100, 40), reason: 'the option is highlighted');
      expect(boxes.single.cause.cause, 'server_error');
    });

    test('a missing field is recorded; the box opens only when it fails again, and that is a "repeat" case', () async {
      AppMonitoring.callFailed('saveQuickItem', 'invalid-argument', 'Enter the price.');
      expect(boxes, isEmpty);
      AppMonitoring.callFailed('saveQuickItem', 'invalid-argument', 'Enter the price.');
      expect(boxes.single.cause.cause, 'missing_field', reason: 'one box, the second time');
      final list = await problems();
      expect(list.map((p) => p['kind']), containsAll(['api', 'repeat']));
      expect(list.firstWhere((p) => p['kind'] == 'repeat')['cause'], 'missing_field');
    });

    test('three taps on the same option with no screen change: "no answer"; a screen change in between: not', () async {
      final t = DateTime(2026, 11, 17, 12);
      DifficultyWatch.tapped('Save item', const Offset(50, 50), now: t);
      DifficultyWatch.tapped('Save item', const Offset(52, 51), now: t.add(const Duration(seconds: 1)));
      DifficultyWatch.routeToken++;
      DifficultyWatch.tapped('Save item', const Offset(50, 50), now: t.add(const Duration(seconds: 2)));
      expect(boxes, isEmpty);
      DifficultyWatch.tapped('Save item', const Offset(50, 50), now: t.add(const Duration(seconds: 3)));
      DifficultyWatch.tapped('Save item', const Offset(50, 50), now: t.add(const Duration(seconds: 4)));
      expect(boxes.single.kind, 'tap');
      expect(boxes.single.option, 'Save item');
      DifficultyWatch.tapped('+', const Offset(9, 9), now: t);
      DifficultyWatch.tapped('+', const Offset(9, 9), now: t);
      DifficultyWatch.tapped('+', const Offset(9, 9), now: t);
      expect(boxes, hasLength(1), reason: 'a quantity + is tapped again on purpose');
      final list = await problems();
      expect(list.single['message'], 'No answer to "Save item" after 3 taps');
    });
  });

  testWidgets('a screen stuck loading is found; a finished one is not', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator()))));
    expect(DifficultyWatch.hasVisibleLoading(tester.binding.rootElement!), isTrue);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator(value: 0.4)))));
    expect(DifficultyWatch.hasVisibleLoading(tester.binding.rootElement!), isFalse, reason: 'a progress with a value is moving on');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Done'))));
    expect(DifficultyWatch.hasVisibleLoading(tester.binding.rootElement!), isFalse);
  });

  testWidgets('the screenshot covers every text field (passwords, OTP, payment, anything typed)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: ScreenCapture.boundaryKey,
        child: const Scaffold(body: Column(children: [Text('Sign in'), TextField(obscureText: true), TextField(), SensitiveArea(child: Text('UPI: someone@bank'))])),
      ),
    ));
    final boundary = tester.renderObject(find.byKey(ScreenCapture.boundaryKey));
    final rects = ScreenCapture.sensitiveRects(boundary);
    expect(rects, hasLength(3), reason: 'two text fields and the sensitive area');
    final upi = tester.getRect(find.text('UPI: someone@bank'));
    expect(rects.any((r) => r.contains(upi.center)), isTrue);
  });

  testWidgets('the shell highlights the option of a case and opens the box once per problem', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    AppMonitoring.reset();
    AppMonitoring.start(app: 'customer');
    final opened = <String>[];
    SupportShellState.shown.clear();
    SupportShell.boxBuilder = (context, store, c, close) => Positioned(right: 0, top: 0, child: TextButton(key: const ValueKey('test-box'), onPressed: () { opened.add(c.fingerprint); close(); }, child: Text(c.message)));
    addTearDown(() {
      SupportShell.boxBuilder = null;
      AppMonitoring.reset();
      store.dispose();
    });
    await tester.pumpWidget(MaterialApp(builder: (context, child) => withSupportShell(context, child, store), home: const Scaffold(body: Text('shop'))));
    AppMonitoring.fail('upload', 'Photo upload (items): unknown', option: 'Add photo', rect: const Rect.fromLTWH(20, 100, 120, 48));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('support-highlight')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-box')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('test-box')));
    await tester.pump();
    AppMonitoring.fail('upload', 'Photo upload (items): unknown', option: 'Add photo');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('test-box')), findsNothing, reason: 'the same problem does not open the box again in a session');
    await tester.pump(const Duration(seconds: 7));
    expect(find.byKey(const ValueKey('support-highlight')), findsNothing);
  });
}
