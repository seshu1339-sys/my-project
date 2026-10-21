import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/layout_editor.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';

Future<Store> _store([Map<String, Map<String, dynamic>> sections = const {}]) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  for (final e in sections.entries) {
    await store.save('settings', Entry('section_${e.key}', {...e.value, 'section': e.key}));
  }
  return store;
}

Future<void> _form(WidgetTester tester, Store store, String component, {List<String>? fields}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: LayoutFieldsForm(store: store, component: component, fieldsOverride: fields))),
  ));
}

Future<void> _openAdvanced(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Advanced'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Advanced'));
  await tester.pumpAndSettle();
}

TextEditingController _box(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(ValueKey(key))).controller!;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('contradictory sizes', () {
    test('width below its minimum, height below its minimum, minimum above maximum', () {
      final c = layoutConflicts({'width': 900, 'minWidth': 1000, 'height': 10, 'minHeight': 50});
      expect(c.length, 2);
      expect(c[0].keys, ['width', 'minWidth']);
      expect(c[0].message, 'The width (900 px) is smaller than the minimum width (1000 px). Raise the width or lower the minimum.');
      expect(c[1].keys, ['height', 'minHeight']);
      expect(c[1].message, contains('The height (10 px) is smaller than the minimum height (50 px)'));
      final both = layoutConflicts({'minWidth': 800, 'maxWidth': 400});
      expect(both.single.message, 'Minimum width (800 px) is larger than the maximum width (400 px). Lower the minimum or raise the maximum.');
      final tooBig = layoutConflicts({'height': 900, 'maxHeight': 500});
      expect(tooBig.single.keys, ['height', 'maxHeight']);
      expect(tooBig.single.message, contains('larger than the maximum height'));
    });

    test('screen-specific widths are checked against the same limits', () {
      final c = layoutConflicts({'mobileWidth': 300, 'minWidth': 360, 'desktopWidth': 2000, 'maxWidth': 1200});
      expect(c.map((e) => e.keys.first), ['mobileWidth', 'desktopWidth']);
      expect(c.first.message, contains('mobile width (300 px)'));
    });

    test('blank / 0 means automatic and never conflicts; consistent sizes pass', () {
      expect(layoutConflicts({'width': 0, 'minWidth': 1000}), isEmpty);
      expect(layoutConflicts({'width': 900, 'minWidth': 0, 'maxWidth': 0}), isEmpty);
      expect(layoutConflicts({'width': 900, 'minWidth': 600, 'maxWidth': 1200, 'height': 80, 'minHeight': 50, 'maxHeight': 120}), isEmpty);
      expect(layoutConflicts({}), isEmpty);
    });

    testWidgets('the Search Box with width 900 / min 1000 and height 10 / min 50 is refused with a clear message', (tester) async {
      final store = await _store();
      await _form(tester, store, 'search');
      await _openAdvanced(tester);
      await tester.enterText(find.byKey(const ValueKey('search-width')), '900');
      await tester.enterText(find.byKey(const ValueKey('search-minWidth')), '1000');
      await tester.enterText(find.byKey(const ValueKey('search-height')), '10');
      await tester.enterText(find.byKey(const ValueKey('search-minHeight')), '50');
      await tester.pump();
      final state = tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm));
      expect(await state.save(), isFalse);
      await tester.pumpAndSettle();
      expect(store.entries('settings').where((e) => e.id == 'section_search'), isEmpty, reason: 'nothing was saved');
      expect(find.textContaining('Not saved: The width (900 px) is smaller than the minimum width (1000 px)'), findsOneWidget);
      // the fields that disagree show the reason too
      expect(find.textContaining('The height (10 px) is smaller than the minimum height (50 px)'), findsWidgets);
      // fixing one is not enough; fixing both saves
      await tester.enterText(find.byKey(const ValueKey('search-minWidth')), '600');
      await tester.pump();
      expect(await state.save(), isFalse);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('search-minHeight')), '10');
      await tester.pump();
      expect(await state.save(), isTrue);
      final saved = store.entries('settings').firstWhere((e) => e.id == 'section_search');
      expect(saved.number('width'), 900);
      expect(saved.number('minWidth'), 600);
      expect(saved.number('height'), 10);
    });

    testWidgets('while sizes contradict, the Visual Editor\'s auto-save writes nothing', (tester) async {
      final store = await _store();
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LayoutFieldsForm(store: store, component: 'search', autoSave: true)))));
      await _openAdvanced(tester);
      await tester.enterText(find.byKey(const ValueKey('search-width')), '900');
      await tester.enterText(find.byKey(const ValueKey('search-minWidth')), '1000');
      await tester.pump(const Duration(seconds: 2));
      expect(store.entries('settings').where((e) => e.id == 'section_search'), isEmpty);
      await tester.enterText(find.byKey(const ValueKey('search-minWidth')), '500');
      await tester.pump(const Duration(seconds: 2));
      expect(store.entries('settings').firstWhere((e) => e.id == 'section_search').number('minWidth'), 500);
    });
  });

  group('Small / Medium / Large and Advanced', () {
    test('a preset sets the screen scales when a component has them, else its font size, else its icon size', () {
      expect(presetValues('small', ['visible', 'mobileScale', 'tabletScale', 'desktopScale', 'height']), {'mobileScale': '0.85', 'tabletScale': '0.85', 'desktopScale': '0.85'});
      expect(presetValues('large', ['mobileScale', 'tabletScale', 'desktopScale']), {'mobileScale': '1.2', 'tabletScale': '1.2', 'desktopScale': '1.2'});
      expect(presetValues('medium', ['mobileScale', 'desktopScale']), {'mobileScale': '', 'desktopScale': ''});
      expect(presetValues('small', ['visible', 'fontSize']), {'fontSize': '12'});
      expect(presetValues('large', ['fontSize', 'iconSize']), {'fontSize': '18'});
      expect(presetValues('large', ['iconSize']), {'iconSize': '36'});
      expect(presetValues('medium', ['iconSize']), {'iconSize': ''});
      expect(presetValues('small', ['visible', 'textColor']), isEmpty, reason: 'no size fields: no preset');
    });

    test('which preset the current values amount to', () {
      const fields = ['mobileScale', 'tabletScale', 'desktopScale'];
      expect(presetOf({'mobileScale': '', 'tabletScale': '', 'desktopScale': ''}, fields), 'medium');
      expect(presetOf({'mobileScale': '1', 'tabletScale': '1.0', 'desktopScale': '1'}, fields), 'medium');
      expect(presetOf({'mobileScale': '0.85', 'tabletScale': '0.85', 'desktopScale': '0.85'}, fields), 'small');
      expect(presetOf({'mobileScale': '1.2', 'tabletScale': '1.2', 'desktopScale': '1.2'}, fields), 'large');
      expect(presetOf({'mobileScale': '0.9', 'tabletScale': '', 'desktopScale': ''}, fields), isNull);
    });

    testWidgets('Small / Medium / Large size a component in one tap, and Advanced shows the exact numbers', (tester) async {
      final store = await _store();
      await _form(tester, store, 'categories');
      expect(find.byKey(const ValueKey('size-preset')), findsOneWidget);
      // Advanced is closed to begin with: the pixel boxes are not on screen
      expect(find.byKey(const ValueKey('categories-height')), findsNothing);
      await tester.tap(find.text('Small'));
      await tester.pumpAndSettle();
      await _openAdvanced(tester);
      expect(_box(tester, 'categories-mobileScale').text, '0.85');
      expect(_box(tester, 'categories-desktopScale').text, '0.85');
      await tester.tap(find.text('Large'));
      await tester.pumpAndSettle();
      expect(_box(tester, 'categories-tabletScale').text, '1.2');
      expect(await tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm)).save(), isTrue);
      expect(store.entries('settings').firstWhere((e) => e.id == 'section_categories').number('mobileScale'), 1.2);
      await tester.tap(find.text('Medium'));
      await tester.pumpAndSettle();
      expect(_box(tester, 'categories-mobileScale').text, '');
      expect(find.text('Fine-tune in Advanced'), findsOneWidget);
      // typing a custom value leaves the presets unselected
      await tester.enterText(find.byKey(const ValueKey('categories-mobileScale')), '0.9');
      await tester.pumpAndSettle();
      expect(find.text('Custom sizes (see Advanced)'), findsOneWidget);
    });

    testWidgets('a preset never touches colours, text or other settings', (tester) async {
      final store = await _store({'categories': {'textColor': '#112233', 'backgroundColor': '#445566', 'height': 200}});
      await _form(tester, store, 'categories');
      await tester.tap(find.text('Small'));
      await tester.pumpAndSettle();
      expect(await tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm)).save(), isTrue);
      final saved = store.entries('settings').firstWhere((e) => e.id == 'section_categories');
      expect(saved.text('textColor'), '#112233');
      expect(saved.text('backgroundColor'), '#445566');
      expect(saved.number('height'), 200);
      expect(saved.number('desktopScale'), 0.85);
    });

    testWidgets('behaviour pages (their own field list) are not split into Advanced', (tester) async {
      final store = await _store();
      await _form(tester, store, 'promo', fields: const ['visibleCount', 'animationMs', 'animationType', 'animationSpeed']);
      expect(find.text('Advanced'), findsNothing);
      expect(find.byKey(const ValueKey('size-preset')), findsNothing);
      expect(find.byKey(const ValueKey('promo-visibleCount')), findsOneWidget);
    });
  });
}
