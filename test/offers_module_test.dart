import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ecommerce_app/modules/modules.dart';
import 'package:ecommerce_app/modules/offers/admin_offers.dart';
import 'package:ecommerce_app/modules/offers/offer_model.dart';
import 'package:ecommerce_app/modules/offers/offers_module.dart';
import 'package:ecommerce_app/modules/offers/offers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 2, 10);

// A real 1x1 PNG, so the photo preview in the editor can draw it.
final pixel = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

VendorOffer offer({String id = 'o1', String status = 'live', String shopId = 's1', DateTime? endsAt, num? regular = 299, String reason = '', List<String> photos = const []}) => VendorOffer(
  id: id,
  vendorId: 'v1',
  shopId: shopId,
  shopName: 'Lakshmi Sweets',
  title: 'Diwali box $id',
  details: 'Fresh box',
  offerPrice: 199,
  regularPrice: regular,
  photos: photos,
  status: status,
  removedReason: reason,
  endsAt: endsAt ?? now.add(const Duration(days: 3)),
);

Widget _page(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> _openEditor(WidgetTester tester, {VendorOffer? offer, void Function(OfferDraft?)? done}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final draft = await showDialog<OfferDraft>(
              context: context,
              builder: (_) => OfferEditorDialog(offer: offer, now: now, pickPhoto: () async => NewOfferPhoto(null, pixel)),
            );
            done?.call(draft);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, {String title = 'Diwali box', String price = '199', String regular = ''}) async {
  await tester.enterText(find.byKey(const ValueKey('offer-title')), title);
  await tester.enterText(find.byKey(const ValueKey('offer-price')), price);
  await tester.enterText(find.byKey(const ValueKey('offer-regular-price')), regular);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('offer-save')));
  await tester.pumpAndSettle();
}

void main() {
  test('the module has its own route and collection, and a home box', () {
    expect(offersRoute, '/vendor-offers');
    expect(offersCollection, 'vendorOffers');
    final module = homeModules.singleWhere((m) => m.id == 'offers');
    expect(module.title, 'Shop Offers');
    expect(module.route, offersRoute);
  });

  test('a document becomes an offer', () {
    final read = VendorOffer.fromData('o1', {
      'vendorId': 'v1',
      'shopId': 's1',
      'shopName': 'Lakshmi',
      'title': 'Box',
      'offerPrice': 199.5,
      'photos': ['a'],
      'status': 'live',
      'endsAt': Timestamp.fromDate(now),
    });
    expect(read.regularPrice, isNull);
    expect(read.details, '');
    expect(read.photos, ['a']);
    expect(read.endsAt, now);
    expect(offerPriceText(read.offerPrice), '₹199.50');
    expect(offerPriceText(199), '₹199');
  });

  test('a customer sees only live, unfinished offers of the shops given, soonest ending first', () {
    final later = offer(id: 'later', endsAt: now.add(const Duration(days: 9)));
    final soon = offer(id: 'soon', endsAt: now.add(const Duration(days: 1)));
    final seen = offersForCustomer([
      later,
      soon,
      offer(id: 'ended', endsAt: now),
      offer(id: 'waiting', status: 'pending'),
      offer(id: 'removed', status: 'removed'),
      offer(id: 'hidden shop', shopId: 'other'),
    ], {'s1'}, now);
    expect(seen.map((o) => o.id), ['soon', 'later']);
  });

  test('the status line tells the vendor where an offer stands', () {
    expect(offerStatusText(offer(), now), 'Live until 5/11/2026');
    expect(offerStatusText(offer(status: 'pending'), now), 'Waiting for approval, until 5/11/2026');
    expect(offerStatusText(offer(endsAt: now.subtract(const Duration(days: 1))), now), 'Ended on 1/11/2026');
    expect(offerStatusText(offer(status: 'removed', reason: 'Wrong photo'), now), 'Removed by the administrator: Wrong photo');
  });

  testWidgets('customers see the offer with prices, and its details open with the shop button', (tester) async {
    VendorOffer? opened;
    await tester.pumpWidget(_page(OffersView(offers: [offer()], located: true, onShop: (o) => opened = o)));
    expect(find.text('Diwali box o1'), findsOneWidget);
    expect(find.text('₹199'), findsOneWidget);
    expect(find.text('₹299'), findsOneWidget);
    expect(find.text('Lakshmi Sweets'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('offer-o1')));
    await tester.pumpAndSettle();
    expect(find.text('Fresh box'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('offer-open-shop')));
    await tester.pumpAndSettle();
    expect(opened?.id, 'o1');
    expect(find.text('Fresh box'), findsNothing);
  });

  testWidgets('with no offers the page says so, and by location when one is chosen', (tester) async {
    await tester.pumpWidget(_page(const OffersView(offers: [], located: true)));
    expect(find.text('No offers near you right now.'), findsOneWidget);
    await tester.pumpWidget(_page(const OffersView(offers: [], located: false)));
    expect(find.text('No offers right now.'), findsOneWidget);
  });

  testWidgets('the editor needs a name, a price above 0, a regular price above it and a photo', (tester) async {
    OfferDraft? draft;
    await _openEditor(tester, done: (d) => draft = d);
    await _save(tester);
    expect(find.text('Enter an offer name'), findsOneWidget);
    expect(find.text('Enter a price above 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('offer-photo-error')), findsOneWidget);
    await _fill(tester, regular: '100');
    await _save(tester);
    expect(find.text('Must be above the offer price'), findsOneWidget);
    await _fill(tester, regular: '299');
    await tester.tap(find.byKey(const ValueKey('offer-add-photo')));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(draft?.fields, {'title': 'Diwali box', 'details': '', 'offerPrice': 199, 'regularPrice': 299, 'days': 7, 'alert': false});
    expect(draft?.newPhotos, hasLength(1));
  });

  testWidgets('a new offer may alert customers within the plan km (a switch); editing a running one never asks again', (tester) async {
    OfferDraft? draft;
    await _openEditor(tester, done: (d) => draft = d);
    await _fill(tester);
    await tester.tap(find.byKey(const ValueKey('offer-take-photo')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('offer-alert')));
    await tester.tap(find.byKey(const ValueKey('offer-alert')));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(draft?.fields['alert'], isTrue);
    expect(draft?.newPhotos, hasLength(1), reason: 'Take photo adds a photo too');

    await _openEditor(tester, offer: offer(photos: const ['https://example.com/a.webp']), done: (d) => draft = d);
    expect(find.byKey(const ValueKey('offer-alert')), findsNothing);
    await _save(tester);
    expect(draft?.fields.containsKey('alert'), isFalse);
  });

  test('the vendor reads what happened to the alert, never a number', () {
    VendorOffer withAlert(String status, {int km = 25, String offerStatus = 'live'}) =>
        VendorOffer.fromData('o', {'title': 'T', 'offerPrice': 10, 'status': offerStatus, 'alertRadiusKm': km, 'alertStatus': status});
    expect(offerAlertText(withAlert('', km: 0)), isNull);
    expect(offerAlertText(VendorOffer.fromData('o', {'title': 'T', 'offerPrice': 10, 'status': 'live', 'alert': true})), 'Alert within your plan km');
    expect(offerAlertText(withAlert('sent')), 'Alert sent to customers within 25 km');
    expect(offerAlertText(withAlert('daily-limit', km: 50)), 'Alert not sent: one alert a day. Your offer is live.');
    expect(offerAlertText(withAlert('no-shop-location')), startsWith('Alert not sent: your shop has no map location'));
    expect(offerAlertText(withAlert('', offerStatus: 'pending')), 'The alert within 25 km goes when the offer is approved');
  });

  testWidgets('photos stop at three', (tester) async {
    await _openEditor(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('offer-add-photo')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('offer-add-photo')), findsNothing);
  });

  testWidgets('editing a running offer keeps its end date unless the vendor changes it', (tester) async {
    OfferDraft? draft;
    await _openEditor(tester, offer: offer(photos: const ['https://example.com/a.webp']), done: (d) => draft = d);
    expect(find.text('Keep end date (5/11/2026)'), findsOneWidget);
    await _save(tester);
    expect(draft?.fields.containsKey('days'), isFalse);
    expect(draft?.fields['offerId'], 'o1');
    expect(draft?.keptPhotos, ['https://example.com/a.webp']);
  });

  testWidgets('running a finished offer again asks for new days', (tester) async {
    OfferDraft? draft;
    await _openEditor(tester, offer: offer(endsAt: now, photos: const ['https://example.com/a.webp']), done: (d) => draft = d);
    expect(find.textContaining('Keep end date'), findsNothing);
    await _save(tester);
    expect(draft?.fields['days'], 7);
  });

  testWidgets('My Offers lists the vendor\'s offers; a removed one can only be deleted', (tester) async {
    final deleted = <String>[];
    await tester.pumpWidget(_page(VendorOffersView(
      offers: [offer(status: 'removed', id: 'gone', reason: 'Wrong photo'), offer()],
      now: now,
      onSave: (_) async {},
      onDelete: (id) async => deleted.add(id),
    )));
    expect(find.textContaining('Live until 5/11/2026'), findsOneWidget);
    expect(find.textContaining('Wrong photo'), findsOneWidget);
    expect(find.byKey(const ValueKey('offer-edit-o1')), findsOneWidget);
    expect(find.byKey(const ValueKey('offer-edit-gone')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('offer-delete-gone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('offer-delete-yes')));
    await tester.pumpAndSettle();
    expect(deleted, ['gone']);
  });

  testWidgets('every offer screen fits a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final offers = [offer(), offer(id: 'wait', status: 'pending'), offer(id: 'gone', status: 'removed', reason: 'Wrong photo')];
    await tester.pumpWidget(_page(OffersView(offers: offers, located: true)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_page(SingleChildScrollView(child: VendorOffersView(offers: offers, now: now, onSave: (_) async {}, onDelete: (_) async {}))));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_page(AdminOffersView(offers: offers, approvalRequired: true, now: now, onApproval: (_) async {}, onApprove: (_) async {}, onRemove: (_, _) async {})));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OfferEditorDialog(offer: offer(photos: const ['https://example.com/a.webp']), now: now)),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the admin approves a waiting offer, removes with a reason, and has the approval switch', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_page(AdminOffersView(
      offers: [offer(), offer(id: 'wait', status: 'pending')],
      approvalRequired: false,
      now: now,
      onApproval: (on) async => calls.add('approval $on'),
      onApprove: (id) async => calls.add('approve $id'),
      onRemove: (id, reason) async => calls.add('remove $id $reason'),
    )));
    expect(tester.getTopLeft(find.byKey(const ValueKey('admin-offer-wait'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('admin-offer-o1'))).dy), reason: 'waiting offers come first');
    expect(find.byKey(const ValueKey('admin-offer-approve-o1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('admin-offer-approve-wait')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-offer-remove-o1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('offer-remove-yes')));
    await tester.pumpAndSettle();
    expect(find.text('Give a short reason'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('offer-remove-reason')), 'Wrong photo');
    await tester.tap(find.byKey(const ValueKey('offer-remove-yes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('offers-approval')));
    await tester.pumpAndSettle();
    expect(calls, ['approve wait', 'remove o1 Wrong photo', 'approval true']);
  });
}
