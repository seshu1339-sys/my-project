// Location-based offers: the town-name helpers, then the real customer page (MarketApp) switching offers, ads and the banner's area
// name. Since 11 Nov 2026 who sees an offer is decided by its SHOP's distance only (lib/domain/reach.dart): no town lists, no
// district or state offers, no offers "for everyone".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/towns.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/location_picker_dialog.dart';
import 'places_fixture.dart';

Entry _promo(String id, String placement, {String locations = '', String shop = ''}) => Entry(
  id,
  {
    'name': id,
    'placement': placement,
    'locations': locations,
    if (shop.isNotEmpty) 'radiusShopId': shop,
    'active': true,
    'order': 0,
  },
);

// A shop in each town, and each town's point.
const _shops = [
  Entry('narsi', {'name': 'Narsipatnam shop', 'latitude': 17.667, 'longitude': 82.612}),
  Entry('anaka', {'name': 'Anakapalle shop', 'latitude': 17.691, 'longitude': 83.003}),
];
const _points = {'Narsipatnam': (17.668, 82.613), 'Anakapalle': (17.690, 83.002), 'Visakhapatnam': (17.734, 83.279)};
Future<void> _goTo(Store store, String town) =>
    store.setLocation('', '', lat: _points[town]!.$1, lng: _points[town]!.$2, town: town, area: town);

Future<Store> _store({
  String towns = 'Narsipatnam=531116|531115, Anakapalle=531001, Visakhapatnam',
  Map<String, dynamic> business = const {},
  List<Entry> promotions = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  await store.save('settings', Entry('business', {
    'name': 'Local Market',
    'serviceTowns': towns,
    ...business,
  }));
  store.catalog['promotions']!.clear();
  store.catalog['shops'] = [..._shops];
  // One discounted item in each shop, for the banner's price chips.
  store.catalog['products'] = const [
    Entry('p-narsi', {'name': 'Narsipatnam rice', 'price': 40, 'compareAtPrice': 50, 'shopId': 'narsi', 'stock': 5}),
    Entry('p-anaka', {'name': 'Anakapalle jaggery', 'price': 60, 'compareAtPrice': 80, 'shopId': 'anaka', 'stock': 5}),
  ];
  for (final promotion in promotions) {
    await store.save('promotions', promotion);
  }
  return store;
}

Future<void> _wide(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('town rules', () {
    final towns = parseServiceTowns(
      'Narsipatnam=531116|531115, Anakapalle=531001\nVisakhapatnam, narsipatnam',
    );

    test('towns list parses names, pincodes and drops duplicates', () {
      expect(towns.map((t) => t.name), [
        'Narsipatnam',
        'Anakapalle',
        'Visakhapatnam',
      ]);
      expect(towns.first.pincodes, ['531116', '531115']);
    });

    test('the town comes from an explicit pick, a pincode, or a place name', () {
      String town({String? pick, String pin = '', String address = ''}) =>
          resolveTown(town: pick, pincode: pin, address: address, towns: towns);
      expect(town(pick: 'narsipatnam'), 'Narsipatnam');
      expect(town(pick: 'Elsewhere'), 'Elsewhere');
      expect(town(pin: '531115'), 'Narsipatnam');
      expect(town(address: '12 Main Rd, Anakapalle, AP'), 'Anakapalle');
      // Street text is never guessed into a town name.
      expect(town(address: '12 Main Road'), '');
      expect(town(address: 'Current GPS location'), '');
      expect(town(pin: '560001'), '');
    });

    test('a searched place gives its first part, or the configured spelling', () {
      expect(
        townFromPlaceName('Elamanchili, Anakapalli, Andhra Pradesh', towns),
        'Elamanchili',
      );
      expect(
        townFromPlaceName('Ward 3, Anakapalle, AP, India', towns),
        'Anakapalle',
      );
    });

    test('only the town\'s offers, else general ones, else nothing', () {
      final all = [
        _promo('narsi', 'carousel', locations: 'Narsipatnam'),
        _promo('anak', 'carousel', locations: 'Anakapalle, Narsipatnam'),
        _promo('everyone', 'carousel'),
      ];
      List<String> ids(String town) =>
          promotionsForTown(all, town).entries.map((e) => e.id).toList();
      expect(ids(''), ['everyone']); // no town chosen: general offers only
      expect(ids('Narsipatnam'), ['narsi', 'anak']);
      expect(ids('narsipatnam'), ['narsi', 'anak']); // case-insensitive
      expect(ids('Anakapalle'), ['anak']);
      final fallback = promotionsForTown(all, 'Visakhapatnam');
      expect(fallback.entries.map((e) => e.id), ['everyone']);
      expect(fallback.usedGeneral, isTrue);
      expect(
        promotionsForTown([all.first], 'Visakhapatnam').entries,
        isEmpty,
      );
    });
  });

  group('store', () {
    test('picking a town, a pincode, and refreshing GPS keep the right town',
        () async {
      final store = await _store();
      await store.setLocation('', '', town: 'Anakapalle');
      expect(store.town, 'Anakapalle');
      // The on-open GPS refresh passes the unchanged pincode/address back.
      await store.setLocation(
        store.pincode,
        store.address,
        lat: 17.7,
        lng: 83.0,
      );
      expect(store.town, 'Anakapalle');
      await store.setLocation('531116', '');
      expect(store.town, 'Narsipatnam');
      await store.setLocation('560001', 'Current GPS location');
      expect(store.town, '');
      store.dispose();
    });

    test('the town survives an app restart', () async {
      final store = await _store();
      await store.setLocation('', '', town: 'Narsipatnam');
      final reopened = Store();
      await reopened.init();
      expect(reopened.town, 'Narsipatnam');
      store.dispose();
      reopened.dispose();
    });
  });

  group('customer page', () {
    testWidgets("offers and ads follow the place: only those of shops within the km; the banner names the area", (tester) async {
      await _wide(tester);
      final store = await _store(
        promotions: [
          // The old town lists no longer count: the shop does.
          _promo('Narsipatnam special', 'carousel', locations: 'Anakapalle', shop: 'narsi'),
          _promo('Anakapalle special', 'carousel', shop: 'anaka'),
          _promo('Narsipatnam ad', 'ad', shop: 'narsi'),
          _promo('Everyone ad', 'ad'),
          _promo('Everyone offer', 'carousel'),
        ],
      );
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();

      await _goTo(store, 'Narsipatnam');
      await tester.pump();
      expect(find.text("Today's Narsipatnam Offers"), findsOneWidget);
      expect(find.text('Narsipatnam special'), findsWidgets);
      expect(find.text('Anakapalle special'), findsNothing);
      expect(find.text('Everyone offer'), findsNothing, reason: 'an offer without a shop is shown to nobody');

      // Changing the location changes the name and the offers at once.
      await _goTo(store, 'Anakapalle');
      await tester.pump();
      expect(find.text("Today's Anakapalle Offers"), findsOneWidget);
      expect(find.text("Today's Narsipatnam Offers"), findsNothing);
      expect(find.text('Anakapalle special'), findsWidgets);
      expect(find.text('Narsipatnam special'), findsNothing);
      expect(find.text('Narsipatnam ad'), findsNothing);

      // No shop with an offer within the km: a message, never another place's offers or "general" ones, never empty boxes.
      await _goTo(store, 'Visakhapatnam');
      await tester.pump();
      expect(find.text("Today's Narsipatnam Offers"), findsNothing);
      expect(find.text("Today's Anakapalle Offers"), findsNothing);
      expect(find.text('Everyone offer'), findsNothing);
      expect(find.byKey(const ValueKey('no-offers-notice')), findsOneWidget);
      expect(find.text('No offers near you right now.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets("a place with no offers near it shows the admin's own message, with the area name", (tester) async {
      await _wide(tester);
      final store = await _store(
        business: {'noOffersMessage': 'Nothing near {town} today'},
        promotions: [_promo('Narsipatnam special', 'carousel', shop: 'narsi')],
      );
      await tester.pumpWidget(MarketApp(store: store));
      await _goTo(store, 'Visakhapatnam');
      await tester.pump();
      expect(find.text('Nothing near Visakhapatnam today'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('the location dialog lists the towns and picks one', (
      tester,
    ) async {
      usePlacesFixture();
      final store = await _store();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLocationPickerDialog(context, store),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('town-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anakapalle').last);
      await tester.pumpAndSettle();
      expect(store.town, 'Anakapalle');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });

  // The offer form's town Location field is gone (owner, 11 Nov 2026): an offer is shown near its shop only (test/radius_test.dart).
}
