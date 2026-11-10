// Agreement to the Terms & Conditions and the Privacy Policy: "By continuing, you agree ..." on the sign-in screens (no tick), links that open the right pages, the one-time
// agreement screen for people already signed in, and no asking once it is saved.
import 'dart:io';

import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/consent.dart';
import 'package:ecommerce_app/ui/consent_checkbox.dart';
import 'package:ecommerce_app/ui/policy_links.dart';
import 'package:ecommerce_app/ui/sign_in_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _GateStore extends Store {
  _GateStore() : super();
  bool needsScreen = true;
  @override
  bool get showsConsentScreen => needsScreen;
}

/// Google that is closed without choosing (no phone in a test).
class _QuietGoogleStore extends Store {
  @override
  Future<bool?> signInWithGoogle({bool automatic = false}) async => false;
  @override
  Future<void> requestEmailCode(String email) async {}
}

Future<Store> _store({String role = 'user', bool consentRequired = true, Map<String, Object> prefs = const {}, Store? google}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = (google ?? Store())
    ..appRole = role
    ..requiresConsent = consentRequired;
  await store.init();
  return store;
}

Future<void> _pump(WidgetTester tester, Widget home, {String language = 'en'}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: Locale(language),
    supportedLocales: [Locale(language)],
    localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    home: Scaffold(body: SingleChildScrollView(child: home)),
  ));
  await tester.pump();
}

bool _enabled(WidgetTester tester, String key) => tester.widget<FilledButton>(find.byKey(ValueKey(key))).onPressed != null;

void main() {
  test('the app and the server agree on the version of the terms', () {
    final server = File('functions/consent.js').readAsStringSync();
    expect(server, contains("POLICY_VERSION = '$policyVersion'"));
  });

  test('the pages people agree to carry the same version date', () {
    expect(policyVersion, '2026-11-04');
    for (final page in ['web/terms/index.html', 'web/privacy/index.html', 'web/privacy-vendor/index.html', 'web/privacy-staff/index.html']) {
      expect(File(page).readAsStringSync(), contains('Effective 4 November 2026'), reason: page);
    }
  });

  test('a phone that already has an agreement saved does not ask on the sign-in screen', () async {
    expect((await _store()).asksConsentBeforeSignIn, isTrue);
    expect((await _store(prefs: {'consent_device': policyVersion})).asksConsentBeforeSignIn, isFalse);
    expect((await _store(prefs: {'consent_device': '2020-01-01'})).asksConsentBeforeSignIn, isTrue, reason: 'new pages are agreed to again');
    expect((await _store(consentRequired: false)).asksConsentBeforeSignIn, isFalse, reason: 'the admin app does not ask');
  });

  testWidgets('the sign-in screen says "By continuing, you agree ..." (no tick box), and continuing with Google is the agreement', (tester) async {
    final store = await _store(google: _QuietGoogleStore());
    await _pump(tester, SignInPanel(store: store));
    expect(find.byKey(const ValueKey('consent-checkbox')), findsNothing, reason: 'no tick box: Google stays one tap');
    final notice = tester.widget<Text>(find.byKey(const ValueKey('consent-notice'))).textSpan!.toPlainText();
    expect(notice, 'By continuing, you agree to the Terms & Conditions and the Privacy Policy.');
    expect(_enabled(tester, 'google-sign-in'), isTrue);
    expect(store.pendingConsent, isFalse);
    await tester.tap(find.byKey(const ValueKey('google-sign-in')));
    await tester.pumpAndSettle();
    expect(store.pendingConsent, isTrue, reason: 'saved on the server right after sign-in, as a tick was');
  });

  testWidgets('sending an email code under the sentence is the agreement too', (tester) async {
    final store = await _store(google: _QuietGoogleStore());
    await _pump(tester, SignInPanel(store: store));
    await tester.tap(find.byKey(const ValueKey('google-sign-in')));
    await tester.pumpAndSettle();
    store.pendingConsent = false;
    await tester.tap(find.byKey(const ValueKey('email-code-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('code-email')), 'new.person@example.com');
    await tester.tap(find.byKey(const ValueKey('send-code')));
    await tester.pumpAndSettle();
    expect(store.pendingConsent, isTrue);
  });

  testWidgets('the sentence is not shown again once an agreement is saved on the phone', (tester) async {
    final store = await _store(prefs: {'consent_device': policyVersion});
    await _pump(tester, SignInPanel(store: store));
    expect(find.byKey(const ValueKey('consent-notice')), findsNothing);
    expect(find.byKey(const ValueKey('consent-checkbox')), findsNothing);
    expect(_enabled(tester, 'google-sign-in'), isTrue);
  });

  testWidgets('the sign-in sentence in Telugu names both pages', (tester) async {
    final store = await _store();
    await _pump(tester, ConsentNotice(store: store), language: 'te');
    final telugu = tester.widget<Text>(find.byKey(const ValueKey('consent-notice'))).textSpan!.toPlainText();
    expect(telugu, 'కొనసాగించడం ద్వారా మీరు నియమాలు & షరతులు మరియు గోప్యతా విధానం ఒప్పుకుంటున్నారు.');
  });

  testWidgets('the sentence names both pages as links, in English by default and in Telugu in simple words', (tester) async {
    final store = await _store();
    await _pump(tester, ConsentCheckbox(store: store));
    final english = tester.widget<Text>(find.byKey(const ValueKey('consent-sentence'))).textSpan!.toPlainText();
    expect(english, 'I agree to the Terms & Conditions and the Privacy Policy.');
    await _pump(tester, ConsentCheckbox(store: store), language: 'te');
    final telugu = tester.widget<Text>(find.byKey(const ValueKey('consent-sentence'))).textSpan!.toPlainText();
    expect(telugu, 'నేను నియమాలు & షరతులు మరియు గోప్యతా విధానం ఒప్పుకుంటున్నాను.');
    await _pump(tester, ConsentCheckbox(store: store), language: 'hi');
    expect(tester.widget<Text>(find.byKey(const ValueKey('consent-sentence'))).textSpan!.toPlainText(), contains('गोपनीयता नीति'));
  });

  test('each app links its own privacy page and the shared terms page, and both exist', () {
    expect(PolicyLinks.privacyPath('user'), '/privacy');
    expect(PolicyLinks.privacyPath('vendor'), '/privacy-vendor');
    expect(PolicyLinks.privacyPath('staff'), '/privacy-staff');
    for (final path in ['/terms', '/privacy', '/privacy-vendor', '/privacy-staff']) {
      expect(File('web$path/index.html').existsSync(), isTrue, reason: path);
    }
  });

  testWidgets('a signed-in person without an agreement sees the screen over the app and must tick before continuing', (tester) async {
    final store = _GateStore()
      ..requiresConsent = true;
    await store.init();
    await tester.pumpWidget(MaterialApp(builder: (context, child) => withConsentGate(context, child, store), home: const Scaffold(body: Text('the app'))));
    await tester.pump();
    expect(find.byKey(const ValueKey('consent-screen')), findsOneWidget);
    expect(find.text('Before you continue'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('consent-agree'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('consent-checkbox')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('consent-agree'))).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('consent-logout')), findsOneWidget);
    store.needsScreen = false;
    store.consentChanged();
    await tester.pump();
    expect(find.byKey(const ValueKey('consent-screen')), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('without the need the app shows no agreement screen', (tester) async {
    final store = await _store();
    await tester.pumpWidget(MaterialApp(builder: (context, child) => withConsentGate(context, child, store), home: const Scaffold(body: Text('the app'))));
    await tester.pump();
    expect(find.byKey(const ValueKey('consent-screen')), findsNothing);
  });
}
