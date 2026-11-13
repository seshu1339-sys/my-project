import 'package:ecommerce_app/domain/post_duration.dart' show showPostDayChoices;
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/modules/offerdisplay/offerdisplay_module.dart';
import 'package:ecommerce_app/modules/offerrotation/offerrotation_module.dart';
import 'package:ecommerce_app/modules/offerstore/offerstore_module.dart';
import 'package:ecommerce_app/modules/premiumadmin/admin_premium.dart';
import 'package:ecommerce_app/modules/premiumadmin/admin_premium_data.dart';
import 'package:ecommerce_app/modules/premiumadmin/wholesale_form.dart';
import 'package:ecommerce_app/modules/premiumscreen/premiumscreen_module.dart';
import 'package:ecommerce_app/modules/wholesale/wholesale_module.dart';
import 'package:ecommerce_app/ui/home_hero_carousel.dart';
import 'package:ecommerce_app/ui/home_vendor_offers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

final now = DateTime(2026, 11, 2, 10);
final pixel = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

TodaysOffer offer(String id, {String shop = 's1', DateTime? ends, DateTime? submitted}) => TodaysOffer(
  vendorId: id,
  shopId: shop,
  photoUrl: 'https://example.com/$id.webp',
  price: 99,
  submittedAt: submitted ?? now,
  endsAt: ends ?? now.add(const Duration(hours: 24)),
);

WholesaleOffer wholesale(String id) => WholesaleOffer(id: id, name: 'Basmati rice', photoUrl: 'https://example.com/w.webp', price: 1200, minQuantity: '25 kg', validUntil: DateTime(2026, 12, 31), wholesaler: 'Sri Traders', phone: '9876543210');

Widget page(Widget child) => MaterialApp(home: Scaffold(body: child));

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // These tests check the vendor's own day choices, which the app hides (lib/domain/post_duration.dart): switched on here.
  setUp(() => showPostDayChoices = true);
  tearDown(() => showPostDayChoices = false);
  group('rotation: the order of the boxes', () {
    test('admin offers come first, then vendor offers, and none is left out however many', () {
      final vendors = [for (var i = 0; i < 40; i++) 'v$i'];
      final merged = mergeOffers(['a1', 'a2'], vendors);
      expect(merged.length, 42);
      expect(merged.take(3), ['a1', 'a2', 'v0']);
      expect(fillBoxes(merged, ['p1'], 6), merged, reason: 'with more than fit, only offers');
    });

    test('with 6 or fewer offers, promotions fill the boxes left; with none, promotions as they are', () {
      expect(fillBoxes(['o1', 'o2'], ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'], 6), ['o1', 'o2', 'p1', 'p2', 'p3', 'p4']);
      expect(fillBoxes(['o1', 'o2', 'o3', 'o4', 'o5', 'o6'], ['p1'], 6).length, 6);
      expect(fillBoxes(<String>[], ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'], 6).length, 7);
    });

    Widget carousel(int count) => page(Center(
      child: HeroCarousel(
        entries: [for (var i = 0; i < count; i++) Entry('e$i', const {})],
        appearance: const Entry('promo', {'visibleCount': 6, 'animationMs': 3000}),
        onTap: (_) {},
        speed: 200,
        boxBuilder: (context, look, i) => Text('offer $i'),
      ),
    ));

    testWidgets('the boxes go on to the next set and loop back; a partial last set is filled from the start', (tester) async {
      setSize(tester, const Size(1400, 900));
      await tester.pumpWidget(carousel(7));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        expect(find.text('offer $i'), findsOneWidget);
      }
      expect(find.text('offer 6'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('offer 6'), findsOneWidget, reason: 'the last offer gets its turn');
      expect(find.text('offer 0'), findsOneWidget, reason: 'the empty boxes take the first offers');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('offer 5'), findsOneWidget, reason: 'back at the first set');
      expect(find.text('offer 6'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with 6 offers the boxes stay put', (tester) async {
      setSize(tester, const Size(1400, 900));
      await tester.pumpWidget(carousel(6));
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      for (var i = 0; i < 6; i++) {
        expect(find.text('offer $i'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the customer side', () {
    test('only running offers of shops in the circle, earliest submitted first', () {
      final first = offer('first', submitted: now.subtract(const Duration(hours: 5)));
      final seen = vendorOffersForCustomer([
        offer('second'),
        first,
        offer('ended', ends: now),
        offer('far', shop: 'other'),
      ], {'s1'}, now);
      expect(seen.map((o) => o.vendorId), ['first', 'second']);
      expect(vendorOffersForCustomer([offer('x')], {}, now), isEmpty, reason: 'no known location: no vendor offers');
    });

    testWidgets('a box has the photo on top and the price below, nothing else, and a tap goes to the shop', (tester) async {
      var taps = 0;
      await tester.pumpWidget(page(SizedBox(
        width: 200,
        height: 220,
        child: VendorOfferBox(photoUrl: '', price: '₹99', frame: const BoxDecoration(color: Colors.green), colour: Colors.green, radius: 12, onTap: () => taps++),
      )));
      final photo = tester.getRect(find.byKey(const ValueKey('vendor-offer-photo')));
      final price = tester.getRect(find.byKey(const ValueKey('vendor-offer-price')));
      expect(photo.bottom <= price.top, isTrue);
      expect(find.byType(Text), findsOneWidget, reason: 'only the price is text');
      await tester.tap(find.text('₹99'));
      expect(taps, 1);
    });
  });

  group('the vendor screen', () {
    const items = [
      OfferItemChoice(id: 'p1', name: 'Tomato', photoUrl: 'https://example.com/t.webp', price: 40),
      OfferItemChoice(id: 'p2', name: 'Onion', photoUrl: 'https://example.com/o.webp'),
    ];
    Future<void> openForm(WidgetTester tester, Future<void> Function(OfferFormResult) sent, {int boxes = 3, List<RunningOffer> offers = const []}) async {
      setSize(tester, const Size(1000, 1400));
      await tester.pumpWidget(page(TodaysOfferPanel(offers: offers, boxes: boxes, items: items, dayOptions: todaysOfferDays, onSubmit: sent)));
      await tester.tap(find.byKey(const ValueKey('todays-offer-fill-1')));
      await tester.pumpAndSettle();
    }

    testWidgets('the plan decides the number of boxes; each empty box says so', (tester) async {
      setSize(tester, const Size(1000, 1400));
      await tester.pumpWidget(page(TodaysOfferPanel(offers: const [], boxes: 3, items: items, dayOptions: todaysOfferDays, onSubmit: (_) async {})));
      expect(find.text("Your plan gives 3 Today's Offers boxes. Customers within your plan's km see them."), findsOneWidget);
      for (final slot in [1, 2, 3]) expect(find.byKey(ValueKey('todays-offer-empty-$slot')), findsOneWidget);
      expect(find.byKey(const ValueKey('todays-offer-box-4')), findsNothing);
    });

    testWidgets('the form takes an item, a price and 1 week to 3 months, and each is needed', (tester) async {
      OfferFormResult? sent;
      await openForm(tester, (r) async => sent = r);
      expect(find.byType(TextFormField), findsNWidgets(2), reason: 'the price and the optional offer text (owner, 13 Nov 2026)');
      for (final words in ['1 week', '1 month', '2 months', '3 months']) expect(find.text(words), findsOneWidget, reason: words);
      await tester.tap(find.byKey(const ValueKey('todays-offer-send')));
      await tester.pump();
      expect(find.text('Enter a price above 0'), findsOneWidget);
      expect(find.text('Choose an item'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('todays-offer-item-p1')));
      await tester.pump();
      expect(tester.widget<TextFormField>(find.byKey(const ValueKey('todays-offer-price'))).controller!.text, '40', reason: 'the item price is offered to start from');
      await tester.enterText(find.byKey(const ValueKey('todays-offer-price')), '35.5');
      await tester.tap(find.byKey(const ValueKey('todays-offer-send')));
      await tester.pump();
      expect(find.text('Choose how long it shows'), findsOneWidget, reason: 'no time is chosen for the vendor');
      await tester.tap(find.byKey(const ValueKey('todays-offer-days-60')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('todays-offer-send')));
      await tester.pumpAndSettle();
      expect([sent?.productId, sent?.price, sent?.days, sent?.slot], ['p1', 35.5, 60, 1]);
      expect(find.text('Your offer is live'), findsOneWidget);
    });

    testWidgets('a refused offer shows the server\'s reason', (tester) async {
      await openForm(tester, (_) async => throw StateError('needs a Silver, Gold or Premium plan'));
      await tester.enterText(find.byKey(const ValueKey('todays-offer-price')), '99');
      await tester.tap(find.byKey(const ValueKey('todays-offer-item-p2')));
      await tester.tap(find.byKey(const ValueKey('todays-offer-days-7')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('todays-offer-send')));
      await tester.pumpAndSettle();
      expect(find.textContaining('needs a Silver, Gold or Premium plan'), findsOneWidget);
    });

    testWidgets('a running box shows LIVE in its colour, the item, price and end, with Change and Remove', (tester) async {
      final removed = <int>[];
      await tester.pumpWidget(page(TodaysOfferPanel(
        offers: [RunningOffer(photoUrl: 'https://example.com/a.webp', price: 99, endsAt: DateTime(2026, 12, 3, 9, 5), slot: 2, productId: 'p1', name: 'Tomato', days: 30)],
        boxes: 2,
        items: items,
        dayOptions: todaysOfferDays,
        onSubmit: (_) async {},
        onRemove: (slot) async => removed.add(slot),
      )));
      expect(find.byKey(const ValueKey('todays-offer-empty-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('todays-offer-live-2')), findsOneWidget);
      expect(find.text('Tomato'), findsOneWidget);
      expect(find.text('₹99'), findsOneWidget);
      expect(find.text('Shows until 3/12/2026'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('todays-offer-remove-2')));
      await tester.pumpAndSettle();
      expect(removed, [2]);
    });

    testWidgets('the large box fills the screen below the offer box, down to the bottom', (tester) async {
      setSize(tester, const Size(390, 800));
      await tester.pumpWidget(MaterialApp(
        home: PremiumOfferScreen(
          offerBox: const SizedBox(key: ValueKey('top'), height: 100),
          largeBox: WholesaleList(offers: [wholesale('w1')], onCall: (_) {}),
        ),
      ));
      final top = tester.getRect(find.byKey(const ValueKey('top')));
      final large = tester.getRect(find.byKey(const ValueKey('wholesale-box')));
      expect(large.top, greaterThanOrEqualTo(top.bottom));
      expect(large.bottom, closeTo(800, 16));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wholesale card has everything on it, and a tap calls the number', (tester) async {
      setSize(tester, const Size(320, 640));
      final called = <String>[];
      await tester.pumpWidget(page(WholesaleList(offers: [wholesale('w1')], onCall: called.add)));
      for (final text in ['Basmati rice', '₹1200 wholesale', 'Minimum: 25 kg', 'Valid until 31/12/2026', 'Sri Traders', '9876543210']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      await tester.tap(find.byKey(const ValueKey('wholesale-w1')));
      expect(called, ['9876543210']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no wholesale offers is said plainly', (tester) async {
      await tester.pumpWidget(page(WholesaleList(offers: const [], onCall: (_) {})));
      expect(find.byKey(const ValueKey('wholesale-empty')), findsOneWidget);
    });
  });

  test('documents become offers', () {
    final read = TodaysOffer.fromData('v1', {'shopId': 's1', 'photoUrl': 'u', 'price': 99.5, 'submittedAt': Timestamp.fromDate(now), 'endsAt': Timestamp.fromDate(now)});
    expect(read.vendorId, 'v1');
    expect(read.liveAt(now), isFalse, reason: 'ended at its end time');
    expect(read.liveAt(now.subtract(const Duration(seconds: 1))), isTrue);
    final card = WholesaleOffer.fromData('w1', {'name': 'Rice', 'price': 10, 'validUntil': Timestamp.fromDate(now)});
    expect(card.validUntil, now);
    expect(card.phone, '');
  });

  group('the admin tab', () {
    Widget view({List<AdminWholesale> items = const [], List<AdminVendorOffer> offers = const [], Future<void> Function(WholesaleDraft)? onSave, Future<void> Function(String)? onDelete, Future<void> Function(String)? onRemove}) => page(AdminPremiumView(
      wholesale: items,
      vendorOffers: offers,
      now: now,
      shopName: (id) => 'Shop $id',
      onSave: onSave ?? (_) async {},
      onDelete: onDelete ?? (_) async {},
      onRemoveOffer: onRemove ?? (_) async {},
    ));

    final rice = AdminWholesale(id: 'w1', name: 'Rice', photoUrl: 'https://example.com/w.webp', price: 1200, minQuantity: '25 kg', validUntil: DateTime(2026, 12, 31), wholesaler: 'Sri Traders', phone: '9876543210');

    testWidgets('the form needs every field; the validity is the end of the chosen day', (tester) async {
      setSize(tester, const Size(1000, 1400));
      WholesaleDraft? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved = await showDialog<WholesaleDraft>(
                context: context,
                builder: (_) => WholesaleFormDialog(now: now, pickPhoto: () async => XFile.fromData(pixel, name: 'w.png'), pickDate: () async => DateTime(2026, 12, 31)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-save')));
      await tester.pump();
      expect(find.text('Enter the item name'), findsOneWidget);
      expect(find.text('Enter a price above 0'), findsOneWidget);
      expect(find.text('Add a photo'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('wholesale-name')), 'Rice');
      await tester.enterText(find.byKey(const ValueKey('wholesale-price')), '1200');
      await tester.enterText(find.byKey(const ValueKey('wholesale-min')), '25 kg');
      await tester.enterText(find.byKey(const ValueKey('wholesale-wholesaler')), 'Sri Traders');
      await tester.enterText(find.byKey(const ValueKey('wholesale-phone')), '9876543210');
      await tester.tap(find.byKey(const ValueKey('wholesale-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-save')));
      await tester.pumpAndSettle();
      expect(saved?.fields['validUntil'], DateTime(2026, 12, 31, 23, 59, 59).millisecondsSinceEpoch);
      expect(saved?.photo, isNotNull);
    });

    testWidgets('the admin deletes a wholesale offer and removes a vendor\'s offer, after asking', (tester) async {
      setSize(tester, const Size(1000, 1400));
      final calls = <String>[];
      await tester.pumpWidget(view(
        items: [rice],
        offers: [AdminVendorOffer(vendorId: 'v1', shopId: 's1', photoUrl: 'https://example.com/a.webp', price: 99, endsAt: DateTime(2026, 11, 3))],
        onDelete: (id) async => calls.add('delete $id'),
        onRemove: (id) async => calls.add('remove $id'),
      ));
      expect(find.text('Shop s1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('admin-wholesale-delete-w1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('premium-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-vendor-offer-remove-v1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('premium-confirm')));
      await tester.pumpAndSettle();
      expect(calls, ['delete w1', 'remove v1']);
    });

    testWidgets('the tab fits a small phone', (tester) async {
      setSize(tester, const Size(320, 640));
      await tester.pumpWidget(view(items: [rice], offers: [AdminVendorOffer(vendorId: 'v1', shopId: 's1', photoUrl: 'https://example.com/a.webp', price: 99, endsAt: DateTime(2026, 11, 3))]));
      expect(tester.takeException(), isNull);
    });
  });
}
