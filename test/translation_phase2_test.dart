// Phase 2 of the screen-label translation work: account, email-link,
// services, product/shop/cart screens. Checks the translation tables
// themselves (shape, placeholders) and that the real screens pick them up.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/services/strings_account.dart';
import 'package:ecommerce_app/services/strings_details.dart';
import 'package:ecommerce_app/services/strings_table.dart';
import 'package:ecommerce_app/ui/account.dart';
import 'package:ecommerce_app/ui/cart_page.dart';
import 'package:ecommerce_app/ui/email_link.dart';

final _placeholder = RegExp(r'\{[a-z0-9]+\}');

Set<String> _placeholders(String text) =>
    _placeholder.allMatches(text).map((m) => m.group(0)!).toSet();

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  return store;
}

Future<void> _pumpTelugu(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(MaterialApp(
      locale: const Locale('te'),
      supportedLocales: const [Locale('te')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ));
  await tester.pump();
}

void main() {
  final tables = {
    'account': accountTranslations,
    'details': detailsTranslations,
  };

  test('every phase 2 row covers all ten languages with no blank text', () {
    for (final entry in tables.entries) {
      expect(entry.value, isNotEmpty, reason: entry.key);
      for (final row in entry.value.entries) {
        expect(
          row.value.keys.toSet(),
          translationColumns.toSet(),
          reason: '${entry.key}: "${row.key}"',
        );
        for (final text in row.value.values) {
          expect(text.trim(), isNotEmpty, reason: '"${row.key}"');
        }
      }
    }
  });

  test('every translation keeps the same {placeholders} as its English text', () {
    for (final entry in tables.entries) {
      for (final row in entry.value.entries) {
        final expected = _placeholders(row.key);
        for (final language in row.value.entries) {
          expect(
            _placeholders(language.value),
            expected,
            reason: '${entry.key}: "${row.key}" [${language.key}]',
          );
        }
      }
    }
  });

  test('the two tables never define the same English text twice', () {
    expect(
      accountTranslations.keys.toSet().intersection(
        detailsTranslations.keys.toSet(),
      ),
      isEmpty,
    );
  });

  test('buildTranslations rejects a row with the wrong number of languages', () {
    expect(
      () => buildTranslations(const [
        ['Hello', 'नमस्ते'],
      ]),
      throwsStateError,
    );
  });

  testWidgets('the account page shows Telugu labels', (tester) async {
    final store = await _store();
    await _pumpTelugu(tester, AccountPage(store: store));
    expect(find.text('మీ ఖాతా'), findsOneWidget);
    expect(find.text('మీరు డెమోను చూస్తున్నారు'), findsOneWidget);
    expect(find.text('You’re exploring the demo'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the email-link page shows Telugu labels', (tester) async {
    final store = await _store();
    await _pumpTelugu(tester, EmailLinkPage(store: store));
    expect(find.text('ఈమెయిల్ లింక్ సైన్-ఇన్'), findsOneWidget);
    expect(find.text('పాస్‌వర్డ్ లేకుండా సైన్ ఇన్ చేయండి'), findsOneWidget);
    expect(find.text('సైన్-ఇన్ లింక్ పంపండి'), findsOneWidget);
    expect(find.text('Send sign-in link'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the empty cart shows Telugu labels', (tester) async {
    final store = await _store();
    await _pumpTelugu(tester, CartPage(store: store));
    expect(find.text('మీ షాపింగ్ బ్యాగ్'), findsOneWidget);
    expect(find.text('మీ తదుపరి స్థానిక కనుగోలు ఇక్కడ ఉంటుంది.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
