import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/moderation_dialogs.dart';

void main() {
  group('runModerationAction', () {
    testWidgets('shows the onSuccess-formatted message on success', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        ctx = context;
        return ElevatedButton(
          onPressed: () => runModerationAction(
            ctx,
            () async => {'itemsChanged': 3},
            onSuccess: (r) => 'Changed ${r['itemsChanged']}',
          ),
          child: const Text('go'),
        );
      }))));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('Changed 3'), findsOneWidget);
    });

    testWidgets('defaults to "Saved" when onSuccess is omitted', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        ctx = context;
        return ElevatedButton(
          onPressed: () => runModerationAction(ctx, () async => {}),
          child: const Text('go'),
        );
      }))));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets("shows the error's own toString() verbatim on failure, unmodified", (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        ctx = context;
        return ElevatedButton(
          onPressed: () => runModerationAction(ctx, () async => throw StateError('boom')),
          child: const Text('go'),
        );
      }))));
      await tester.tap(find.text('go'));
      await tester.pump();
      // No "Bad state: " stripping here, unlike shared.dart's message().
      expect(find.text('Bad state: boom'), findsOneWidget);
    });
  });
}
