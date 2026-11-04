// Agreement to the Terms & Conditions and the Privacy Policy: a tick before signing up, links that open the right pages, the one-time
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

Future<Store> _store({String role = 'user', bool consentRequired = true, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = Store()
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

  testWidgets('Google and email-code sign-in wait for the tick, then work', (tester) async {
    final store = await _store();
    await _pump(tester, SignInPanel(store: store));
    expect(find.byKey(const ValueKey('consent-checkbox')), findsOneWidget);
    expect(find.text('Tick the box to agree before you continue.'), findsOneWidget);
    expect(_enabled(tester, 'google-sign-in'), isFalse);
    await tester.tap(find.byKey(const ValueKey('consent-checkbox')));
    await tester.pump();
    expect(store.pendingConsent, isTrue);
    expect(_enabled(tester, 'google-sign-in'), isTrue);
    expect(find.text('Tick the box to agree before you continue.'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('consent-checkbox')));
    await tester.pump();
    expect(_enabled(tester, 'google-sign-in'), isFalse, reason: 'unticking closes it again');
  });

  testWidgets('the tick box is not shown again once an agreement is saved on the phone', (tester) async {
    final store = await _store(prefs: {'consent_device': policyVersion});
    await _pump(tester, SignInPanel(store: store));
    expect(find.byKey(const ValueKey('consent-checkbox')), findsNothing);
    expect(_enabled(tester, 'google-sign-in'), isTrue);
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
