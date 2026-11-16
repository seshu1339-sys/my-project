import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/fresh_strip.dart';
import 'package:ecommerce_app/domain/item_shops.dart';
import 'package:ecommerce_app/ui/home_today_offers.dart';
import 'package:ecommerce_app/ui/shared.dart';
import 'package:ecommerce_app/ui/vendor_section_rates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Owner, 16 Nov 2026: prices never run out, the "Today's rate" tick, items without a price never hidden, all 6 Today's Offers boxes
// always shown, and the customer app reading the catalog once per open and per place.
class _RecordingStore extends Store {
  _RecordingStore() : super(live: false);
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls.add(name);
    return {'ratesConfirmedAt': DateTime.now().toUtc().toIso8601String()};
  }
}

void main() {
  test('an item with no price says "Local vendor not updated item price" instead of a price', () {
    expect(priceOrNotUpdated(0), 'Local vendor not updated item price');
    expect(priceOrNotUpdated(45), '₹45');
    const picks = [ItemPick(name: 'Brinjal', imageUrl: 'http://x/brinjal.png')];
    final cards = freshStripProducts(picks, const [Entry('b1', {'name': 'Brinjal', 'price': 0})], '');
    expect(cards.single.id, 'b1', reason: 'the item still shows when its vendor has no price');
  });

  testWidgets("Today's Offers: all 6 boxes show even with no offer anywhere; an empty box says \"Local vendor not updated offer\"", (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['promotions'] = [];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TodayOffersSection(store: store, boxes: const [], appearance: const Entry('promo', {'visibleCount': 6}), empty: const Text('admin message', key: ValueKey('no-offers-notice')), vendorOffers: Stream.value(const [])))));
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      expect(find.byKey(ValueKey('today-offer-empty-$i')), findsOneWidget);
    }
    expect(find.text(noLocalOfferText), findsNWidgets(6));
    expect(find.text("Today's Offer"), findsNWidgets(6), reason: 'the same box with its title');
    expect(find.byKey(const ValueKey('no-offers-notice')), findsOneWidget, reason: "the admin's own message stays, under the boxes");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('vendor home: "Yes, same rates" saves the one confirmation; the app joins the vendors\' topic for the daily reminder', (tester) async {
    final store = _RecordingStore();
    final joined = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: VendorRatesCard(store: store, uid: 'v1', joinTopic: (t) async => joined.add(t))))));
    await tester.pump();
    expect(joined, ['vendors']);
    expect(find.text("Are today's rates the same?"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vendor-same-rates')));
    await tester.pumpAndSettle();
    expect(store.calls, ['confirmTodaysRates'], reason: 'one call: one field on the vendor, never a write per item');
  });

  test('the customer app reads once per open; another pincode or a move of more than 1 km reads again, the on-open GPS refresh does not', () {
    expect(Store(live: true).loadsOnce, isTrue, reason: 'the customer app');
    expect((Store(live: true)..appRole = 'admin').loadsOnce, isFalse);
    expect((Store(live: true)..appRole = 'vendor').loadsOnce, isFalse);
    expect((Store(live: true)..appRole = 'staff').loadsOnce, isFalse);
    expect(Store().loadsOnce, isFalse, reason: 'no Firebase');
    expect(Store.placeMoved(('531116', 17.667, 82.611), ('531116', 17.6675, 82.6112)), isFalse, reason: 'a few metres');
    expect(Store.placeMoved(('531116', 17.667, 82.611), ('531116', 17.70, 82.611)), isTrue, reason: 'about 3.7 km');
    expect(Store.placeMoved(('531116', 17.667, 82.611), ('530008', 17.667, 82.611)), isTrue, reason: 'another pincode');
    expect(Store.placeMoved(('', null, null), ('', 17.7, 83.2)), isTrue, reason: 'a place where there was none');
  });

  test("the tick is checked on the phone by comparing times: a shop's \"Yes, same rates\" covers every price of the shop", () {
    final now = DateTime.utc(2026, 11, 16, 6);
    const shop = Entry('s1', {'ratesConfirmedAt': '2026-11-16T01:00:00.000Z'});
    expect(todaysRate(const Entry('p', {'price': 30, 'priceSetAt': '2026-10-01T00:00:00.000Z'}), shop, now), isTrue);
    expect(todaysRate(const Entry('p', {'price': 30}), const Entry('s2', {'ratesConfirmedAt': '2026-11-14T01:00:00.000Z'}), now), isFalse);
  });
}
