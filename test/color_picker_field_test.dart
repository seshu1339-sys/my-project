import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/color_picker_field.dart';

void main() {
  // The default flutter_test surface is only ~266x200 logical px — too
  // small to fit the picker dialog's preset grid plus its action buttons,
  // which made "Apply"/"Use default" hit-test off-screen below. Every test
  // that opens the dialog needs a realistic size instead.
  void setRealisticSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('ColorPickerField', () {
    testWidgets('shows "Default" and a blocked swatch when unset', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ColorPickerField(
        label: 'Background color',
        value: '',
        onChanged: (_) {},
      ))));
      expect(find.text('Default'), findsOneWidget);
      expect(find.byIcon(Icons.block), findsOneWidget);
    });

    testWidgets('shows the hex value (uppercased) when set', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ColorPickerField(
        label: 'Background color',
        value: '#16a34a',
        onChanged: (_) {},
      ))));
      expect(find.text('#16A34A'), findsOneWidget);
      expect(find.byIcon(Icons.block), findsNothing);
    });

    testWidgets('tapping a preset swatch and Apply commits that hex value', (tester) async {
      setRealisticSize(tester);
      String? committed;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ColorPickerField(
        label: 'Background color',
        value: '',
        onChanged: (v) => committed = v,
      ))));
      await tester.tap(find.byType(ColorPickerField));
      await tester.pumpAndSettle();
      expect(find.text('Choose a color'), findsOneWidget);
      // Tap the first preset swatch — scoped to inside the dialog, since the
      // field itself (still in the tree, underneath the modal barrier) has
      // its own InkWell too and would otherwise be matched first.
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(InkWell)).first);
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(committed, '#16A34A');
    });

    testWidgets('"Use default" clears the value to an empty string', (tester) async {
      setRealisticSize(tester);
      String? committed;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ColorPickerField(
        label: 'Background color',
        value: '#16a34a',
        onChanged: (v) => committed = v,
      ))));
      await tester.tap(find.byType(ColorPickerField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use default'));
      await tester.pumpAndSettle();
      expect(committed, '');
    });

    testWidgets('Cancel does not call onChanged at all', (tester) async {
      setRealisticSize(tester);
      var calls = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ColorPickerField(
        label: 'Background color',
        value: '#16a34a',
        onChanged: (_) => calls++,
      ))));
      await tester.tap(find.byType(ColorPickerField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });

    testWidgets('typing a hex value and tapping Apply commits the typed value', (tester) async {
      setRealisticSize(tester);
      String? committed;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ColorPickerField(
        label: 'Background color',
        value: '',
        onChanged: (v) => committed = v,
      ))));
      await tester.tap(find.byType(ColorPickerField));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '#RRGGBB'), '#ABCDEF');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(committed, '#ABCDEF');
    });
  });
}
