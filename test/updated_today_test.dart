import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/item_shops.dart';
import 'package:ecommerce_app/ui/item_shops_page.dart';

// "Today's rate" (owner, 16 Nov 2026): a green tick for 24 hours from the moment the vendor set the price or tapped "Yes, same rates";
// after that only the tick goes, the price stays, with no date and no "old rate" text. Shops with the tick come first.
void main() {
  final now = DateTime.utc(2026, 11, 16, 4, 30);
  Entry product(String? setAt) => Entry('p', {'name': 'Tomato', 'price': 30, 'priceSetAt': ?setAt});

  test('the tick lasts 24 hours from the price or from "Yes, same rates"', () {
    expect(todaysRate(product('2026-11-15T05:00:00.000Z'), null, now), isTrue, reason: '23 h 30 min ago');
    expect(todaysRate(product('2026-11-15T04:00:00.000Z'), null, now), isFalse, reason: 'more than 24 hours');
    expect(todaysRate(product(null), null, now), isFalse);
    expect(todaysRate(product('not a date'), null, now), isFalse);
    const shop = Entry('s', {'ratesConfirmedAt': '2026-11-16T02:00:00.000Z'});
    expect(todaysRate(product('2026-11-01T04:00:00.000Z'), shop, now), isTrue, reason: 'the vendor confirmed the same rates today');
  });

  test("the item's shops: the ones with the tick first, then the rest, each part as it came (lowest price first)", () {
    ItemOffer offer(String id, double price, String? setAt) => ItemOffer(product: Entry(id, {'price': price, 'priceSetAt': ?setAt}), shop: null, price: price);
    final offers = [offer('cheap-old', 20, '2026-11-10T00:00:00.000Z'), offer('mid-today', 25, '2026-11-16T01:00:00.000Z'), offer('dear-old', 30, null), offer('dear-today', 35, '2026-11-16T03:00:00.000Z')];
    expect(todaysRatesFirst(offers, now).map((o) => o.product.id), ['mid-today', 'dear-today', 'cheap-old', 'dear-old']);
  });

  testWidgets("the shop row shows the tick only for a price of the last 24 hours, and never a date", (tester) async {
    Widget tile(String setAt) => MaterialApp(
      home: Scaffold(
        body: ItemOfferTile(
          offer: ItemOffer(product: Entry('p1', {'name': 'Tomato', 'price': 30, 'unit': '1 kg', 'priceSetAt': setAt}), shop: const Entry('s', {'name': 'Lakshmi Kirana'}), price: 30),
          onTap: () {},
          now: () => now,
        ),
      ),
    );
    await tester.pumpWidget(tile('2026-11-16T02:00:00.000Z'));
    expect(find.byKey(const ValueKey('todays-rate-p1')), findsOneWidget);
    expect(find.text("Today's rate"), findsOneWidget);
    await tester.pumpWidget(tile('2026-11-05T10:00:00.000Z'));
    expect(find.byKey(const ValueKey('todays-rate-p1')), findsNothing);
    expect(find.textContaining('₹30'), findsOneWidget, reason: 'the price stays');
    expect(find.textContaining('ago'), findsNothing);
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
