import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/today_offers.dart';
import 'package:ecommerce_app/services/customer_position.dart';
import 'package:ecommerce_app/services/road_route.dart';
import 'package:ecommerce_app/ui/admin_today_offers.dart';
import 'package:ecommerce_app/ui/home_today_offers.dart';
import 'package:ecommerce_app/ui/shop_route_map.dart';

Entry offer(String id, int slot, String from, String to, {String name = 'Tomato', double price = 25, String town = 'Narsipatnam'}) => Entry(id, {
  'placement': 'offer',
  'slot': slot,
  'name': name,
  'offerPrice': price,
  'unit': '1 kg',
  'shopId': 'shopA',
  'town': town,
  'imageUrl': 'http://x/$id.png',
  'startsAt': from,
  'endsAt': to,
});

void main() {
  final now = DateTime.utc(2026, 10, 26, 6);
  test('each box shows its offer only between its start and end; the next one waits; a box with none is empty', () {
    final offers = [
      offer('a', 1, '2026-10-26T00:00:00Z', '2026-10-26T12:00:00Z'),
      offer('b', 1, '2026-10-26T12:00:00Z', '2026-10-26T20:00:00Z', name: 'Onion'),
      offer('c', 2, '2026-10-25T00:00:00Z', '2026-10-26T05:00:00Z', name: 'ended'),
      offer('d', 3, '2026-10-26T05:00:00Z', '2026-10-27T00:00:00Z', name: 'Potato'),
      offer('e', 3, '2026-10-26T05:30:00Z', '2026-10-26T09:00:00Z', name: 'Carrot'), // overlaps d, starts later: shows
      offer('f', 7, '2026-10-26T00:00:00Z', '2026-10-27T00:00:00Z', name: 'no box'),
      const Entry('carousel', {'placement': 'carousel', 'slot': 4}),
    ];
    final slots = todayOfferSlots(offers, now);
    expect(slots.map((o) => o?.text('name')), ['Tomato', null, 'Carrot', null, null, null]);
    expect(todayOfferSlots(offers, DateTime.utc(2026, 10, 26, 13)).first?.text('name'), 'Onion', reason: 'the next one comes by itself');
    expect(nextTodayOfferChange(offers, now), DateTime.utc(2026, 10, 26, 9));
    expect(overlappingTodayOffers(offers, offers[3]).map((o) => o.id), ['e']);
    expect(overlappingTodayOffers(offers, offers[0]), isEmpty, reason: 'one after another is not an overlap');
    expect(todayOfferRate(offers[0]), '₹25 / 1 kg');
    expect(todayOfferRate(const Entry('x', {'offerPrice': 12.5})), '₹12.50');
    expect([for (final o in offers.take(4)) todayOfferStatus(o, now)], ['Live now', 'Waiting', 'Ended', 'Live now']);
    // the 6 boxes keep the Today's Offers Box promotions' look, then the default colours
    final looks = todayOfferBoxLooks(const [Entry('p1', {'backgroundColor': '#111111'})]);
    expect(looks.map((l) => l.text('backgroundColor')), ['#111111', ...todayOfferDefaultColors.skip(1)]);
  });

  Future<Store> openStore(List<Entry> offers) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['shops'] = [
      const Entry('shopA', {'name': 'Lakshmi Kirana', 'latitude': 17.668, 'longitude': 82.612, 'phone': '9876511111', 'town': 'Narsipatnam', 'address': 'Main Road'}),
    ];
    store.catalog['promotions'] = [
      for (var i = 1; i <= 6; i++) Entry('box$i', {'placement': 'carousel', 'order': i, 'name': "Today's Offer", 'backgroundColor': todayOfferDefaultColors[i - 1]}),
      ...offers,
    ];
    return store;
  }

  testWidgets('the home section: the heading, 6 boxes with photo, name and price, and a tap opens the shop on the map', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CustomerPosition.finder = ({required bool ask}) async => (latitude: 17.667, longitude: 82.611);
    addTearDown(CustomerPosition.reset);
    final live = DateTime.now().toUtc();
    final store = await openStore([
      offer('o1', 2, live.subtract(const Duration(hours: 1)).toIso8601String(), live.add(const Duration(hours: 5)).toIso8601String()),
      offer('o2', 4, live.add(const Duration(hours: 3)).toIso8601String(), live.add(const Duration(hours: 5)).toIso8601String(), name: 'Later'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TodayOffersSection(
          store: store,
          boxes: [for (final p in store.entries('promotions')) if (p.text('placement') == 'carousel') p],
          appearance: const Entry('promo', {'visibleCount': 6}),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text("Today's Offers"), findsOneWidget);
    for (var i = 1; i <= 6; i++) {
      expect(find.byKey(ValueKey('today-offer-box-$i')), findsOneWidget);
    }
    // only box 2 has an offer now: photo in a white circle, name and price in white
    expect(find.descendant(of: find.byKey(const ValueKey('today-offer-box-2')), matching: find.byKey(const ValueKey('today-offer-circle'))), findsOneWidget);
    expect(find.byKey(const ValueKey('today-offer-circle')), findsOneWidget, reason: 'the other boxes are empty');
    expect(find.text('Tomato'), findsOneWidget);
    expect(find.text('₹25 / 1 kg'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Tomato')).style?.color, Colors.white);
    expect(find.text('Later'), findsNothing, reason: 'not started yet');

    await tester.tap(find.text('Tomato'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ShopRouteView), findsOneWidget);
    expect(find.text('Phone: 9876511111'), findsOneWidget);
    expect(find.text('Tomato: ₹25 / 1 kg'), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-route-directions')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the map: the road from the customer, the distance and time by road', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CustomerPosition.finder = ({required bool ask}) async => (latitude: 17.667, longitude: 82.611);
    addTearDown(CustomerPosition.reset);
    final asked = <LatLng>[];
    await tester.pumpWidget(MaterialApp(
      home: ShopRouteView(
        stop: ShopStop.shop(const Entry('shopA', {'name': 'Lakshmi Kirana', 'latitude': 17.668, 'longitude': 82.612, 'phone': '9876511111'}), shopId: 'shopA'),
        route: (from, to) async {
          asked.addAll([from, to]);
          return RoadRoute([from, const LatLng(17.6675, 82.6115), to], meters: 1143, seconds: 110);
        },
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(asked, [const LatLng(17.667, 82.611), const LatLng(17.668, 82.612)]);
    expect(find.text('1.1 km • 2 min by road'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the admin adds an offer: item by name (its photo comes with it), price, shop, box, start and end', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await openStore(const []);
    store.catalog['products'] = [
      const Entry('p1', {'name': 'Tomato', 'price': 32, 'unit': '1 kg', 'shopId': 'shopA', 'imageUrl': 'http://x/tomato.png'}),
    ];
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('admin'))));
    tester.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: TodayOfferForm(store: store, slot: 3, now: DateTime(2026, 10, 26, 9)))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('offer-item-search')), 'tom');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('offer-pick-tomato')));
    await tester.pump();
    expect(find.text('Its photo is used'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('offer-save')));
    await tester.pump();
    expect(find.text('Give the offer price.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('offer-price')), '25');
    await tester.tap(find.byKey(const ValueKey('offer-save')));
    await tester.pumpAndSettle();
    final saved = store.entries('promotions').where(isTodayOffer).single;
    expect(saved.data, containsPair('slot', 3));
    expect(saved.data, containsPair('imageUrl', 'http://x/tomato.png'));
    expect(saved.data, containsPair('shopId', 'shopA'));
    expect(saved.data, containsPair('unit', '1 kg'));
    expect(saved.data, containsPair('town', 'Narsipatnam'));
    expect(saved.number('offerPrice'), 25);
    expect(DateTime.parse(saved.text('startsAt')).toLocal(), DateTime(2026, 10, 26, 9));
    expect(DateTime.parse(saved.text('endsAt')).toLocal(), DateTime(2026, 10, 26, 23, 59), reason: 'the end of the day unless chosen');
    expect(saved.text('description'), '₹25 / 1 kg at Lakshmi Kirana');
  });
}
