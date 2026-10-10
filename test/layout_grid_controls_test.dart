import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/home_product_grid.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';

void main() {
  group('ComponentLayout new grid fields', () {
    test('per-breakpoint columns win over the generic columns field', () {
      final entry = const Entry('', {'columns': 4, 'desktopColumns': 2, 'mobileColumns': 1});
      expect(ComponentLayout(entry, 1440).columns(1000), 2); // desktop
      expect(ComponentLayout(entry, 320).columns(1000), 1); // mobile
      expect(ComponentLayout(entry, 900).columns(1000), 4); // tablet: no override -> generic
    });

    test('rows resolves per-breakpoint first, then the generic field, then unlimited', () {
      expect(ComponentLayout(const Entry('', {}), 1440).rows, 0);
      expect(ComponentLayout(const Entry('', {'rows': 3}), 1440).rows, 3);
      expect(ComponentLayout(const Entry('', {'rows': 3, 'desktopRows': 5}), 1440).rows, 5);
      expect(ComponentLayout(const Entry('', {'rows': 3, 'desktopRows': 5}), 320).rows, 3);
    });

    test('gapX falls back to gap when unset and overrides it when set', () {
      final noOverride = ComponentLayout(const Entry('', {'gap': 20}), 1440);
      expect(noOverride.gapX, noOverride.gap);
      final withOverride = ComponentLayout(const Entry('', {'gap': 20, 'gapX': 5}), 1440);
      expect(withOverride.gapX, 5);
      expect(withOverride.gap, 20);
    });

    test('alignment maps known strings and defaults unknown ones to start', () {
      expect(ComponentLayout(const Entry('', {'alignment': 'center'}), 1440).alignment, WrapAlignment.center);
      expect(ComponentLayout(const Entry('', {'alignment': 'end'}), 1440).alignment, WrapAlignment.end);
      expect(ComponentLayout(const Entry('', {'alignment': 'spaceBetween'}), 1440).alignment, WrapAlignment.spaceBetween);
      expect(ComponentLayout(const Entry('', {'alignment': 'bogus'}), 1440).alignment, WrapAlignment.start);
      expect(ComponentLayout(const Entry('', {}), 1440).alignment, WrapAlignment.start);
    });
  });

  group('HomeProductGrid', () {
    Widget buildGrid(Entry appearance, List<Entry> entries) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: HomeProductGrid(
            entries: entries,
            appearance: appearance,
            itemBuilder: (entry) => Container(
              key: ValueKey('item-${entry.id}'),
              height: 40,
              color: Colors.red,
              child: Text(entry.id),
            ),
          ),
        ),
      ),
    );

    testWidgets('rows caps the number of displayed items to rows * columns', (tester) async {
      final entries = [for (var i = 0; i < 10; i++) Entry('p$i', const {})];
      await tester.pumpWidget(buildGrid(const Entry('', {'columns': 2, 'rows': 1}), entries));
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 2; i++) {
        expect(find.byKey(ValueKey('item-p$i')), findsOneWidget);
      }
      for (var i = 2; i < 10; i++) {
        expect(find.byKey(ValueKey('item-p$i')), findsNothing);
      }
    });

    testWidgets('with rows unset every entry still renders', (tester) async {
      final entries = [for (var i = 0; i < 5; i++) Entry('p$i', const {})];
      await tester.pumpWidget(buildGrid(const Entry('', {'columns': 2}), entries));
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(ValueKey('item-p$i')), findsOneWidget);
      }
    });

    testWidgets('gapX drives horizontal spacing independently from the vertical gap', (tester) async {
      final entries = [for (var i = 0; i < 4; i++) Entry('p$i', const {})];
      await tester.pumpWidget(buildGrid(const Entry('', {'columns': 2, 'gap': 20, 'gapX': 2}), entries));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final wrap = tester.widget<Wrap>(find.byType(Wrap));
      expect(wrap.spacing, 2);
      expect(wrap.runSpacing, 20);
    });
  });
}
