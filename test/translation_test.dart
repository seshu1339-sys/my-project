// Confirms the language switcher actually changes screen labels, not just
// the scrolling ticker (the customer-reported gap this closes).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/main.dart';

void main() {
  testWidgets('switching to Telugu translates home page section labels', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.text('Categories'), findsWidgets);
    expect(find.text('వర్గాలు'), findsNothing);

    await store.setLanguage('te');
    await tester.pump();

    expect(find.text('వర్గాలు'), findsWidgets);
    expect(find.text('జనాదరణ పొందిన ఉత్పత్తులు'), findsNothing); // sanity: wrong string never matches
    expect(find.text('ప్రజాదరణ పొందిన ఉత్పత్తులు'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('a language with no translation entries falls back to English', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();

    // Odia (or) is covered; Assamese (as) is enabled but not translated yet —
    // it must show the English original rather than an empty/garbled string.
    await store.setLanguage('as');
    await tester.pump();

    expect(find.text('Categories'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
