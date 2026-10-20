import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/home_promo_card.dart';
import 'package:ecommerce_app/ui/home_scheduled_promo.dart';

void main() {
  testWidgets(
    'heightOverride forces the same rendered height regardless of the entry\'s own height field -- the exact mechanism the mobile/tablet carousel now uses so every ad is the same size while swiping',
    (tester) async {
      Future<Size> renderedSize(Entry entry) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ScheduledPromo(
                  entry: entry,
                  heightOverride: 260,
                  onTap: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(PromoCard));
      }

      // No height of its own vs. a very different stale per-entry height
      // (as if left over from before per-item resize was removed) -- both
      // must still come out at the SAME forced height.
      final plain = await renderedSize(
        const Entry('ad1', {'name': 'Big Savings Everyday'}),
      );
      final stale = await renderedSize(
        const Entry('ad2', {'name': 'Suma Fresh Mart', 'height': 900.0}),
      );

      expect(plain.height, 260);
      expect(
        stale.height,
        260,
        reason:
            'heightOverride must win over the entry\'s own stale height field',
      );
      expect(plain.height, stale.height);
    },
  );
}
