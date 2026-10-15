import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/color_picker_field.dart';
import 'package:ecommerce_app/ui/layout_editor.dart';

void main() {
  // The admin's font picker genuinely fetches font files over the network
  // in production (that's how google_fonts works) — never acceptable in a
  // sandboxed test run. This falls back to the platform default font
  // instead of fetching, exactly as the package's own README recommends
  // for tests.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<Store> openStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    return store;
  }

  // The default flutter_test surface is only ~266 logical px wide (800
  // physical / devicePixelRatio 3) — far narrower than any real admin
  // screen, and narrow enough to make even reasonably-sized form rows
  // overflow. Every test below needs a realistic width instead.
  void setRealisticSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('LayoutFieldsForm field kinds', () {
    testWidgets('Visible defaults to on, and turning it off saves visible:false', (tester) async {
      final store = await openStore();
      setRealisticSize(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: LayoutFieldsForm(store: store, component: 'categories'))));
      final toggle = find.byKey(const ValueKey('categories-visible'));
      expect(toggle, findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pump();
      // LayoutFieldsForm alone (no LayoutSettingsPage chrome) has no Save
      // button — drive its save() directly via the state instead.
      final state = tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm));
      await state.save();
      expect(
        store.entries('settings').firstWhere((e) => e.id == 'section_categories').data['visible'],
        isFalse,
      );
    });

    testWidgets('a color field renders as ColorPickerField, not a raw text box', (tester) async {
      final store = await openStore();
      setRealisticSize(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: LayoutFieldsForm(store: store, component: 'categories'),
      ))));
      expect(find.byType(ColorPickerField), findsWidgets);
    });

    testWidgets('font family dropdown saves the exact selected family name', (tester) async {
      final store = await openStore();
      setRealisticSize(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: LayoutFieldsForm(store: store, component: 'categories'),
      ))));
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Font family'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poppins').last);
      await tester.pumpAndSettle();
      final state = tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm));
      await state.save();
      expect(
        store.entries('settings').firstWhere((e) => e.id == 'section_categories').text('fontFamily'),
        'Poppins',
      );
    });

    testWidgets('font style dropdown saves italic', (tester) async {
      final store = await openStore();
      setRealisticSize(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: LayoutFieldsForm(store: store, component: 'categories'),
      ))));
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Font style'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Italic').last);
      await tester.pumpAndSettle();
      final state = tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm));
      await state.save();
      expect(
        store.entries('settings').firstWhere((e) => e.id == 'section_categories').text('fontStyle'),
        'italic',
      );
    });

    testWidgets('alignment is 3 buttons (left/center/right), not a text field, and saves the selection', (tester) async {
      final store = await openStore();
      setRealisticSize(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: LayoutFieldsForm(store: store, component: 'popular'),
      ))));
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      await tester.ensureVisible(find.text('Center'));
      await tester.tap(find.text('Center'));
      await tester.pump();
      final state = tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm));
      await state.save();
      expect(
        store.entries('settings').firstWhere((e) => e.id == 'section_popular').text('alignment'),
        'center',
      );
    });

    testWidgets('animation dropdown + Preview button render without crashing', (tester) async {
      final store = await openStore();
      setRealisticSize(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: LayoutFieldsForm(store: store, component: 'categories'),
      ))));
      expect(find.widgetWithText(DropdownButtonFormField<String>, 'Entrance animation'), findsOneWidget);
      await tester.tap(find.text('Preview'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a dimension field shows a "px" suffix', (tester) async {
      final store = await openStore();
      setRealisticSize(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: LayoutFieldsForm(store: store, component: 'categories'),
      ))));
      expect(
        find.descendant(of: find.byKey(const ValueKey('categories-height')), matching: find.text('px')),
        findsOneWidget,
      );
    });

    testWidgets('logo excludes fields that genuinely do nothing for it (width, colors, animation)', (tester) async {
      final store = await openStore();
      setRealisticSize(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: LayoutFieldsForm(store: store, component: 'logo'),
      ))));
      expect(find.byKey(const ValueKey('logo-width')), findsNothing);
      expect(find.byType(ColorPickerField), findsNothing);
      expect(find.widgetWithText(DropdownButtonFormField<String>, 'Entrance animation'), findsNothing);
      // Height remains — it's the one dimension that's actually wired.
      expect(find.byKey(const ValueKey('logo-height')), findsOneWidget);
      // logo still gets Visible, same as every other component.
      expect(find.byKey(const ValueKey('logo-visible')), findsOneWidget);
    });
  });
}
