import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/modules/offerstore/offerstore_module.dart';
import 'package:ecommerce_app/modules/photolimits/item_photos_section.dart';
import 'package:ecommerce_app/modules/plans/plan_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Owner's answers of 7 Nov 2026: Today's Offers boxes per plan, the vendor's search time per item, the item live in Today's Offers marked
// in its own colour.
void main() {
  final now = DateTime(2026, 11, 7, 10);

  // Owner, 13 Nov 2026: Gold 2, Platinum 4, Diamond 6 (Gold was 3).
  test("Today's Offers boxes per plan: Silver 1, Gold 2, Platinum 4, Diamond 6, Premium 5 unless the admin set the plan's own number", () {
    expect(todaysOfferBoxesOf({'tier': 'silver'}), 1);
    expect(todaysOfferBoxesOf({'tier': 'gold'}), 2);
    expect(todaysOfferBoxesOf({'tier': 'platinum'}), 4);
    expect(todaysOfferBoxesOf({'tier': 'diamond'}), 6);
    expect(todaysOfferBoxesOf({'tier': 'premium'}), 5);
    expect(todaysOfferBoxesOf({'tier': 'premium', 'offerBoxes': 8}), 8);
    expect(SubscriptionPlan.fromData('p', {'tier': 'gold'}).offerBoxes, 2);
    expect(SubscriptionPlan.fromData('p', {'tier': 'premium', 'offerBoxes': 7}).offerBoxes, 7);
    expect(todaysOfferDays.values, ['1 week', '1 month', '2 months', '3 months']);
  });

  test('an item shows in search until the time the vendor chose; an item without a choice shows as before', () {
    expect(inSearchAt(const Entry('a', {}), now), isTrue);
    expect(inSearchAt(Entry('b', {'searchUntilMs': now.add(const Duration(days: 1)).millisecondsSinceEpoch}), now), isTrue);
    expect(inSearchAt(Entry('c', {'searchUntilMs': now.millisecondsSinceEpoch}), now), isFalse);
  });

  testWidgets("the vendor's item list: the search time, an ended one in red, and LIVE in Today's Offers in its own colour", (tester) async {
    String? asked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ItemPhotosView(
            allowance: null,
            now: now,
            items: [
              ('p1', {'name': 'Saree', 'searchUntilMs': DateTime(2026, 12, 7).millisecondsSinceEpoch}),
              ('p2', {'name': 'Tomato', 'searchUntilMs': DateTime(2026, 11, 1).millisecondsSinceEpoch}),
              ('p3', {'name': 'Onion'}),
            ],
            inTodaysOffers: {'p1': DateTime(2026, 11, 14)},
            onCamera: (_) {},
            onGallery: (_) {},
            onOurs: (_) {},
            onSearchTime: (id) => asked = id,
          ),
        ),
      ),
    ));
    expect(find.text('Shows in search until 7/12/2026'), findsOneWidget);
    expect(find.textContaining('Not in search now'), findsOneWidget);
    expect(find.byKey(const ValueKey('item-search-p3')), findsNothing);
    expect(find.text("LIVE in Today's Offers until 14/11/2026"), findsOneWidget);
    final badge = tester.widget<Container>(find.byKey(const ValueKey('item-live-offer-p1')));
    expect((badge.decoration as BoxDecoration).color, todaysOfferLiveColour);
    expect(find.byKey(const ValueKey('item-live-offer-p2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('item-photo-menu-p3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How long it shows in search'));
    await tester.pumpAndSettle();
    expect(asked, 'p3');
  });

  testWidgets('the search time dialog offers 1 week to 3 months, 1 month first', (tester) async {
    int? days;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(onPressed: () async => days = await showDialog<int>(context: context, builder: (_) => const SearchTimeDialog()), child: const Text('open'))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final words in searchTimeChoices.values) {
      expect(find.text(words), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('search-time-90')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-time-save')));
    await tester.pumpAndSettle();
    expect(days, 90);
  });
}
