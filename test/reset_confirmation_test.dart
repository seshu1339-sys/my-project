import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/animation_settings_form.dart';
import 'package:ecommerce_app/ui/layout_editor.dart';
import 'package:ecommerce_app/ui/reset_confirmation.dart';

Future<Store> _store(Map<String, Map<String, dynamic>> sections) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  for (final e in sections.entries) {
    await store.save('settings', Entry(e.key, e.value));
  }
  return store;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('describeValue speaks plainly', () {
    expect(describeValue(true), 'On');
    expect(describeValue(false), 'Off');
    expect(describeValue(96.0), '96');
    expect(describeValue(1.2), '1.2');
    expect(describeValue(null), '(not set)');
    expect(describeValue('  '), '(empty)');
  });

  testWidgets('layout reset lists current -> default, Cancel keeps everything', (tester) async {
    final store = await _store({'section_search': {'section': 'search', 'height': 96, 'textColor': '#112233'}});
    await _pump(tester, LayoutFieldsForm(store: store, component: 'search'));
    final state = tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm));
    final future = state.resetToDefault();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reset-row-height')), findsOneWidget);
    expect(find.textContaining('96'), findsWidgets);
    expect(find.textContaining('→'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('reset-cancel')));
    await tester.pumpAndSettle();
    expect(await future, isFalse);
    expect(store.entries('settings').firstWhere((e) => e.id == 'section_search').number('height'), 96);
  });

  testWidgets('layout reset confirmed clears the keys, keeps the rest, and says so', (tester) async {
    final store = await _store({'section_promo': {'section': 'promo', 'height': 96, 'visibleCount': 5}});
    await _pump(tester, LayoutFieldsForm(store: store, component: 'promo'));
    final state = tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm));
    final future = state.resetToDefault();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reset-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Reset complete'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reset-done-ok')));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
    final saved = store.entries('settings').firstWhere((e) => e.id == 'section_promo');
    expect(saved.data.containsKey('height'), isFalse);
    expect(saved.number('visibleCount'), 5, reason: 'behaviour settings are not part of the visual reset');
  });

  testWidgets('nothing to reset says so and shows no dialog', (tester) async {
    final store = await _store({});
    await _pump(tester, LayoutFieldsForm(store: store, component: 'search'));
    final state = tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm));
    expect(await state.resetToDefault(), isTrue);
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Nothing to reset'), findsOneWidget);
  });

  testWidgets('animations reset: confirm lists choices, Confirm removes the record', (tester) async {
    final store = await _store({'animations': {'name': 'Animations', 'enabled': 'false', 'promo_speed': 7}});
    await _pump(tester, SizedBox(height: 2400, child: AdminAnimationsForm(store: store)));
    await tester.ensureVisible(find.byKey(const ValueKey('anim-reset')));
    await tester.tap(find.byKey(const ValueKey('anim-reset')));
    await tester.pumpAndSettle();
    expect(find.text('Reset animations to default?'), findsOneWidget);
    expect(find.byKey(const ValueKey('reset-row-enabled')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reset-cancel')));
    await tester.pumpAndSettle();
    expect(store.entries('settings').any((e) => e.id == 'animations'), isTrue);
    await tester.tap(find.byKey(const ValueKey('anim-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reset-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Reset complete'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reset-done-ok')));
    await tester.pumpAndSettle();
    expect(store.entries('settings').any((e) => e.id == 'animations'), isFalse);
  });
}
