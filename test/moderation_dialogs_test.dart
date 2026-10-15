import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/moderation_dialogs.dart';

void main() {
  group('showSuspensionDialog', () {
    testWidgets('Suspend stays disabled until the reason has 3+ chars, then returns the trimmed reason', (tester) async {
      String? captured;
      bool called = false;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
        ElevatedButton(onPressed: () async {
          called = true;
          captured = await showSuspensionDialog(context, name: 'Acme', suspend: true, suspendBody: 'body', reinstateBody: 'r');
        }, child: const Text('open')),
      ))));
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Suspend')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Suspend')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '  abc  ');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Suspend')).onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
      expect(captured, 'abc');
    });

    testWidgets('reinstate needs no reason and returns an empty string', (tester) async {
      String? captured;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
        ElevatedButton(onPressed: () async {
          captured = await showSuspensionDialog(context, name: 'Acme', suspend: false, suspendBody: 'body', reinstateBody: 'r');
        }, child: const Text('open')),
      ))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Reinstate'));
      await tester.pumpAndSettle();
      expect(captured, '');
    });

    testWidgets('cancel returns null', (tester) async {
      String? captured = 'unset';
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
        ElevatedButton(onPressed: () async {
          captured = await showSuspensionDialog(context, name: 'Acme', suspend: true, suspendBody: 'body', reinstateBody: 'r');
        }, child: const Text('open')),
      ))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(captured, isNull);
    });
  });

  group('showExclusivesDialog', () {
    testWidgets('invalid duration disables Save instead of silently closing', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
        ElevatedButton(
          onPressed: () => showExclusivesDialog(context, name: 'Acme', currentlyEnabled: true, currentMaxDays: 30),
          child: const Text('open'),
        ),
      ))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
      expect(find.text('Enter a maximum duration of 1 day or more.'), findsOneWidget);
    });

    testWidgets('valid duration returns the parsed record', (tester) async {
      ({bool enabled, int? maxDurationDays})? result;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
        ElevatedButton(onPressed: () async {
          result = await showExclusivesDialog(context, name: 'Acme', currentlyEnabled: true, currentMaxDays: 30);
        }, child: const Text('open')),
      ))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '45');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(result, (enabled: true, maxDurationDays: 45));
    });

    testWidgets('disabled returns maxDurationDays null', (tester) async {
      ({bool enabled, int? maxDurationDays})? result;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
        ElevatedButton(onPressed: () async {
          result = await showExclusivesDialog(context, name: 'Acme', currentlyEnabled: true, currentMaxDays: 30);
        }, child: const Text('open')),
      ))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.tap(find.text('Enabled for this vendor'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(result, (enabled: false, maxDurationDays: null));
    });
  });

  group('ApplicationPhoto', () {
    testWidgets('null path renders the placeholder at the given size with a caption when label is given', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ApplicationPhoto(
        label: 'Vendor photo', path: null, height: 150, width: 200,
      ))));
      expect(find.text('No photo'), findsOneWidget);
      expect(find.text('Vendor photo'), findsOneWidget);
      expect(tester.getSize(find.byType(Container)).height, 150);
      expect(tester.getSize(find.byType(Container)).width, 200);
    });

    testWidgets('omitting label suppresses the caption entirely', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ApplicationPhoto(
        path: null, height: 150, width: 200,
      ))));
      expect(find.text('No photo'), findsOneWidget);
      // Only the placeholder's own "No photo" text — no separate caption Text.
      expect(find.byType(Text), findsOneWidget);
    });
  });
}
