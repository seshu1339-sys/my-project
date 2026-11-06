import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/item_shops.dart';
import 'package:ecommerce_app/ui/item_shops_page.dart';

// "Updated today": a price the vendor set today (India date) carries the tag; yesterday's does not; the admin's own products never do.
void main() {
  // 6 Nov 2026, 10:00 India time = 04:30 UTC.
  final now = DateTime.utc(2026, 11, 6, 4, 30);
  Entry product(String? setAt) => Entry('p', {'name': 'Tomato', 'price': 30, 'priceSetAt': ?setAt});

  test('set today in India counts, also just after midnight India time (still the day before in UTC)', () {
    expect(priceUpdatedToday(product('2026-11-06T03:00:00.000Z'), now), isTrue);
    expect(priceUpdatedToday(product('2026-11-05T18:40:00.000Z'), now), isTrue, reason: '00:10 on 6 Nov in India');
  });

  test('set yesterday in India, or with no time at all, has no tag', () {
    expect(priceUpdatedToday(product('2026-11-05T18:20:00.000Z'), now), isFalse, reason: '23:50 on 5 Nov in India');
    expect(priceUpdatedToday(product(null), now), isFalse);
    expect(priceUpdatedToday(product('not a date'), now), isFalse);
  });

  testWidgets('the shop row shows the tag only for today\'s price', (tester) async {
    Widget tile(String setAt) => MaterialApp(
      home: Scaffold(
        body: ItemOfferTile(
          offer: ItemOffer(product: Entry('p1', {'name': 'Tomato', 'price': 30, 'unit': '1 kg', 'priceSetAt': setAt}), shop: const Entry('s', {'name': 'Lakshmi Kirana'}), price: 30),
          onTap: () {},
          now: () => now,
        ),
      ),
    );
    await tester.pumpWidget(tile('2026-11-06T02:00:00.000Z'));
    expect(find.byKey(const ValueKey('updated-today-p1')), findsOneWidget);
    expect(find.text('Updated today'), findsOneWidget);
    await tester.pumpWidget(tile('2026-11-05T10:00:00.000Z'));
    expect(find.byKey(const ValueKey('updated-today-p1')), findsNothing);
  });

  test('searching a category offers its items (owner, 6 Nov 2026: items show for their item or their category)', () {
    const products = [
      Entry('s1', {'name': 'Silk saree', 'price': 1500, 'categoryId': 'sarees'}),
      Entry('s2', {'name': 'Cotton saree', 'price': 600, 'categoryId': 'sarees'}),
      Entry('b1', {'name': 'Bucket', 'price': 120, 'categoryId': 'plastic'}),
    ];
    final names = {for (final c in itemChoices(products, 'sarees', categoryNames: const {'sarees': 'Sarees', 'plastic': 'Plastic'})) c.name};
    expect(names, {'Silk saree', 'Cotton saree'});
    expect({for (final c in itemChoices(products, 'bucket', categoryNames: const {'plastic': 'Plastic'})) c.name}, {'Bucket'});
  });
}
