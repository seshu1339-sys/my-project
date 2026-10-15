import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/visual_editor_overlay.dart';

void main() {
  group('PixelField', () {
    Widget host({required double valuePx, required ValueChanged<double> onChangedPx}) =>
        MaterialApp(home: Scaffold(body: PixelField(
          label: 'Width',
          valuePx: valuePx,
          minPx: 80,
          maxPx: 3840,
          onChangedPx: onChangedPx,
        )));

    testWidgets('shows the value as a whole number of pixels', (tester) async {
      await tester.pumpWidget(host(valuePx: 320, onChangedPx: (_) {}));
      expect(find.text('320'), findsOneWidget);
    });

    testWidgets('tapping + increases by exactly 10px, never reinterpreted as a percentage', (tester) async {
      double? committed;
      await tester.pumpWidget(host(valuePx: 100, onChangedPx: (px) => committed = px));
      await tester.tap(find.byKey(const ValueKey('px-plus-Width')));
      await tester.pump();
      expect(committed, 110.0);
    });

    testWidgets('tapping - decreases by exactly 10px', (tester) async {
      double? committed;
      await tester.pumpWidget(host(valuePx: 100, onChangedPx: (px) => committed = px));
      await tester.tap(find.byKey(const ValueKey('px-minus-Width')));
      await tester.pump();
      expect(committed, 90.0);
    });

    testWidgets('typing an exact pixel value and submitting commits exactly that value', (tester) async {
      double? committed;
      await tester.pumpWidget(host(valuePx: 100, onChangedPx: (px) => committed = px));
      await tester.enterText(find.byKey(const ValueKey('px-field-Width')), '555');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(committed, 555.0, reason: 'whatever number is typed must become exactly that many pixels, not a percentage conversion');
    });

    testWidgets('a value past maxPx clamps to maxPx, not an out-of-range pixel value', (tester) async {
      double? committed;
      await tester.pumpWidget(host(valuePx: 3840, onChangedPx: (px) => committed = px));
      await tester.tap(find.byKey(const ValueKey('px-plus-Width')));
      await tester.pump();
      expect(committed, 3840.0);
    });

    testWidgets('an invalid typed value is ignored rather than committing garbage', (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(valuePx: 100, onChangedPx: (_) => calls++));
      await tester.enterText(find.byKey(const ValueKey('px-field-Width')), 'not a number');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(calls, 0);
    });

    testWidgets('an external value change (e.g. a drag elsewhere) updates the field when not focused, and never resets to a stale value', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PixelField(
        key: key,
        label: 'Height',
        valuePx: 100,
        minPx: 40,
        maxPx: 1200,
        onChangedPx: (_) {},
      ))));
      expect(find.text('100'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PixelField(
        key: key,
        label: 'Height',
        valuePx: 500,
        minPx: 40,
        maxPx: 1200,
        onChangedPx: (_) {},
      ))));
      expect(find.text('500'), findsOneWidget);
    });
  });
}
