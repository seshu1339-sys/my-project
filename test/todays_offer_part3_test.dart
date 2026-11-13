import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ecommerce_app/domain/post_duration.dart';
import 'package:ecommerce_app/modules/offerdisplay/vendor_offer_box.dart';
import 'package:ecommerce_app/modules/offerstore/todays_offer.dart';
import 'package:ecommerce_app/modules/premiumadmin/admin_premium.dart';
import 'package:ecommerce_app/modules/premiumadmin/admin_premium_data.dart';
import 'package:ecommerce_app/modules/premiumscreen/offer_form_dialog.dart';
import 'package:ecommerce_app/modules/premiumscreen/todays_offer_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Part 3 (owner, 13 Nov 2026): Today's Offers boxes from the vendor's items, the catalog or their own photo, a short text, live while the
// plan runs, the admin's Hide / Show / Remove with the Vendor ID and plan.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xff, 0xff, 0x3f,
  0x00, 0x05, 0xfe, 0x02, 0xfe, 0xa7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

Widget _page(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<OfferFormResult?> _form(WidgetTester tester, Future<void> Function() fill) async {
  OfferFormResult? sent;
  _size(tester, const Size(1000, 1600));
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => sent = await showDialog<OfferFormResult>(
            context: context,
            builder: (_) => OfferFormDialog(
              items: const [OfferItemChoice(id: 'p1', name: 'Rice', photoUrl: 'https://example.com/1.jpg')],
              catalog: const [
                OfferItemChoice(id: 'lib-tomato', name: 'Tomato', photoUrl: 'https://example.com/t.jpg', keywords: 'thakkali'),
                OfferItemChoice(id: 'lib-onion', name: 'Onion', photoUrl: 'https://example.com/o.jpg'),
              ],
              dayOptions: const {7: '1 week', 30: '1 month'},
              pickPhoto: () async => _png,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await fill();
  await tester.tap(find.byKey(const ValueKey('todays-offer-send')));
  await tester.pumpAndSettle();
  return sent;
}

void main() {
  final now = DateTime(2027, 1, 10, 9);

  test('customers never see a hidden offer; the vendor still sees it in their boxes', () {
    TodaysOffer offer(Map<String, dynamic> extra) =>
        TodaysOffer.fromData('v1_1', {'vendorId': 'v1', 'shopId': 's1', 'photoUrl': '', 'price': 10, 'endsAt': Timestamp.fromDate(now.add(const Duration(days: 3))), ...extra});
    expect(offer({}).liveAt(now), isTrue);
    expect(offer({'hidden': true}).liveAt(now), isFalse);
    expect(offer({'hidden': true}).runningAt(now), isTrue);
    final read = offer({'note': '2 kg only today', 'untilPlanEnds': true, 'vendorCode': 'VEN-1', 'planName': 'Gold', 'libraryItemId': 'lib-tomato', 'waitingCheck': true});
    expect([read.note, read.untilPlanEnds, read.vendorCode, read.planName, read.libraryItemId, read.waitingCheck], ['2 kg only today', true, 'VEN-1', 'Gold', 'lib-tomato', true]);
  });

  testWidgets('the form: a catalog item found by search, with a short text, runs while the plan runs', (tester) async {
    expect(showPostDayChoices, isFalse);
    final sent = await _form(tester, () async {
      await tester.tap(find.byKey(const ValueKey('todays-offer-source-catalog')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('todays-offer-catalog-search')), 'thakkali');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todays-offer-catalog-lib-onion')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('todays-offer-catalog-lib-tomato')));
      await tester.enterText(find.byKey(const ValueKey('todays-offer-price')), '25');
      await tester.enterText(find.byKey(const ValueKey('todays-offer-note')), '2 kg only today');
    });
    expect([sent?.libraryItemId, sent?.productId, sent?.price, sent?.note, sent?.days, sent?.photo], ['lib-tomato', '', 25, '2 kg only today', null, null]);
  });

  testWidgets('the form: the vendor\'s own photo needs the item name', (tester) async {
    final sent = await _form(tester, () async {
      await tester.tap(find.byKey(const ValueKey('todays-offer-source-photo')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('todays-offer-price')), '180');
      await tester.tap(find.byKey(const ValueKey('todays-offer-send')));
      await tester.pumpAndSettle();
      expect(find.text('Add your photo'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('todays-offer-photo-pick')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todays-offer-photo-preview')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('todays-offer-send')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the item name'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('todays-offer-name')), 'Fresh fish');
    });
    expect([sent?.name, sent?.photo?.length, sent?.productId, sent?.libraryItemId], ['Fresh fish', _png.length, '', '']);
  });

  testWidgets('the vendor\'s box: the text, "while your plan runs", and hidden or waiting marked', (tester) async {
    _size(tester, const Size(1000, 1400));
    await tester.pumpWidget(_page(TodaysOfferPanel(
      offers: [
        RunningOffer(photoUrl: '', price: 25, endsAt: DateTime(2027, 3, 12), slot: 1, name: 'Tomato', note: '2 kg only today', untilPlanEnds: true),
        RunningOffer(photoUrl: '', price: 90, endsAt: DateTime(2027, 3, 12), slot: 2, name: 'Mangoes', untilPlanEnds: true, hidden: true, waitingCheck: true),
        RunningOffer(photoUrl: '', price: 40, endsAt: DateTime(2027, 3, 12), slot: 3, name: 'Rice', untilPlanEnds: true, hidden: true),
      ],
      boxes: 3,
      items: const [],
      dayOptions: const {7: '1 week'},
      onSubmit: (_) async {},
    )));
    expect(find.text('2 kg only today'), findsOneWidget);
    expect(find.text('Live while your plan runs (until 12/3/2027)'), findsNWidgets(3));
    expect(find.byKey(const ValueKey('todays-offer-live-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('todays-offer-waiting-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('todays-offer-hidden-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('todays-offer-hidden-note-3')), findsOneWidget);
  });

  testWidgets('the customer box shows the vendor\'s short text under the price', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 160,
          height: 200,
          child: VendorOfferBox(photoUrl: '', price: '₹25', note: '2 kg only today', frame: const BoxDecoration(color: Colors.green), colour: Colors.green, radius: 12, onTap: () {}),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('vendor-offer-note')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the admin sees the Vendor ID, plan and state of every box, and can Hide, Show and Remove', (tester) async {
    _size(tester, const Size(1000, 1600));
    final calls = <String>[];
    final later = DateTime(2027, 3, 12);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminPremiumView(
      wholesale: const [],
      vendorOffers: [
        AdminVendorOffer(vendorId: 'v1_1', shopId: 's1', photoUrl: '', price: 25, endsAt: later, vendorCode: 'VEN-NRPM-116-325', planName: 'Gold', name: 'Tomato', note: '2 kg only today', untilPlanEnds: true),
        AdminVendorOffer(vendorId: 'v2_1', shopId: 's2', photoUrl: '', price: 90, endsAt: later, vendorCode: 'VEN-2', planName: 'Diamond', hidden: true, waitingCheck: true, ownPhoto: true),
        AdminVendorOffer(vendorId: 'v3_1', shopId: 's3', photoUrl: '', price: 40, endsAt: DateTime(2027, 1, 1), vendorCode: 'VEN-3', planName: 'Silver', untilPlanEnds: true),
      ],
      now: now,
      shopName: (id) => 'Shop $id',
      onSave: (_) async {},
      onDelete: (_) async {},
      onRemoveOffer: (id) async => calls.add('remove $id'),
      onHideOffer: (id, hidden) async => calls.add('${hidden ? 'hide' : 'show'} $id'),
    ))));
    expect(find.text('Vendor ID: VEN-NRPM-116-325 • Plan: Gold'), findsOneWidget);
    expect(find.text('Live while the plan runs (until 12/3/2027)'), findsOneWidget);
    expect(find.textContaining('Waiting for you'), findsOneWidget);
    expect(find.text('Plan ended: hidden until the vendor renews'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin-vendor-offer-hide-v1_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-vendor-offer-show-v2_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-vendor-offer-remove-v3_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('premium-confirm')));
    await tester.pumpAndSettle();
    expect(calls, ['hide v1_1', 'show v2_1', 'remove v3_1']);
  });
}
