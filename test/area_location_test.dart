import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/area_names.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/domain/reach.dart';
import 'package:ecommerce_app/services/area_lookup.dart';
import 'package:ecommerce_app/services/first_location.dart';
import 'package:ecommerce_app/services/geocoding.dart';
import 'package:ecommerce_app/ui/greeting.dart';
import 'package:ecommerce_app/ui/home_ticker_section.dart';

// The customer's AREA name and distance-only offers (owner, 11 Nov 2026): one place everywhere (location box, greeting, "Today's ...
// Offers"), the area people call it (Kancharapalem, Gurudwara), never a street or a big city when a nearer name is known, else the town;
// shops, products and offers only within the admin's one km of the customer, measured to each shop.

// A small directory: Visakhapatnam head office and two of its sub offices that only carry the head office's point, Kancharapalem
// and Gajuwaka with points of their own, Narsipatnam with a sub office of the same pincode, and Chintapalli.
final directory = PlacesIndex.fromJson({
  'states': ['Andhra Pradesh'],
  'districts': [
    ['Visakhapatnam', 0],
  ],
  'places': [
    ['Visakhapatnam', 0, 530001, 2, 17.704, 83.297],
    ['Gandhigram S.O (Visakhapatnam)', 0, 530005, 0, 17.704, 83.297, 'Visakhapatnam'],
    ['Industrial Estate S.O (Visakhapatnam)', 0, 530007, 0, 17.704, 83.297, 'Visakhapatnam'],
    ['Kancharapalem', 0, 530008, 0, 17.734, 83.279, 'Visakhapatnam'],
    ['Gajuwaka', 0, 530026, 0, 17.691, 83.204, 'Visakhapatnam'],
    ['Narsipatnam', 0, 531116, 2, 17.667, 82.612],
    ['Krishna Bazar', 0, 531116, 0, 0, 0, 'Narsipatnam'],
    ['Chintapalli', 0, 531111, 0, 17.870, 82.351],
  ],
});

Future<Store> demoStore({List<Entry> settings = const [], List<Entry> shops = const [], List<Entry> products = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog = {'settings': [...settings], 'shops': [...shops], 'products': [...products], 'promotions': []};
  return store;
}

Position fix(double lat, double lng, {double accuracy = 20}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 11, 11),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  group('the area name', () {
    test('post office and map additions are cleaned off', () {
      expect(cleanAreaName('Anandapuram S.O (Visakhapatnam)'), 'Anandapuram');
      expect(cleanAreaName('Kancharapalem B.O'), 'Kancharapalem');
      expect(cleanAreaName('Old Town H.O.'), 'Old Town');
      expect(cleanAreaName('  Gajuwaka  '), 'Gajuwaka');
    });

    test('the first real area name wins; the town only when none is found; never the town, a ward or a blocked name', () {
      expect(chooseArea(['Kancharapalem', 'Gurudwara'], town: 'Visakhapatnam'), 'Kancharapalem');
      expect(chooseArea(['Visakhapatnam', 'Gajuwaka'], town: 'Visakhapatnam'), 'Gajuwaka', reason: 'the big city name is skipped');
      expect(chooseArea(['Ward 26', 'Zone 3'], town: 'Visakhapatnam'), 'Visakhapatnam');
      expect(chooseArea(const [], town: 'Chintapalli'), 'Chintapalli');
      expect(chooseArea(const [], town: ''), '');
      final names = AreaNames.parse(renames: 'Gurudwara Junction = Gurudwara\nKancharapalem S.O = Kancharapalem', blocked: 'Dwarakanagar');
      expect(chooseArea(['Dwarakanagar', 'Gurudwara Junction'], town: 'Visakhapatnam', names: names), 'Gurudwara');
      expect(chooseArea(['kancharapalem s.o.'], town: 'Visakhapatnam', names: names), 'Kancharapalem', reason: 'case and dots do not matter');
      expect(chooseArea(['Visakhapatnam'], town: 'Visakhapatnam', names: AreaNames.parse(renames: 'Visakhapatnam = Vizag')), 'Vizag');
    });

    test('Settings > Area names are saved as text and read back', () {
      final text = areaRenamesText([('Kancharapalem S.O', 'Kancharapalem'), ('', 'x'), ('Gurudwara Junction', 'Gurudwara')]);
      expect(text, 'Kancharapalem S.O = Kancharapalem\nGurudwara Junction = Gurudwara');
      expect(parseAreaRenames(text), [('Kancharapalem S.O', 'Kancharapalem'), ('Gurudwara Junction', 'Gurudwara')]);
      expect(parseBlockedAreas('Visakhapatnam\n, Vizag \n\n'), ['Visakhapatnam', 'Vizag']);
      final names = AreaNames.from([const Entry(areaNamesId, {'renames': 'A = B', 'blocked': 'C'})]);
      expect(names.renamed('a'), 'B');
      expect(names.isBlocked('c'), isTrue);
    });

    test('OpenStreetMap: the area names around the point, never the road or the house number', () {
      final osm = osmAreaFromJson({
        'address': {
          'house_number': '12-3',
          'road': 'Main Road',
          'neighbourhood': 'Gurudwara Junction',
          'suburb': 'Kancharapalem',
          'city': 'Visakhapatnam',
          'state_district': 'Visakhapatnam',
          'state': 'Andhra Pradesh',
          'postcode': '530 008',
        },
      })!;
      expect(osm.areas, ['Kancharapalem', 'Gurudwara Junction']);
      expect(osm.town, 'Visakhapatnam');
      expect(osm.pincode, '530008');
      expect(osmAreaFromJson({'address': {'road': 'Main Road'}}), isNull);
      expect(osmAreaFromJson('nonsense'), isNull);
    });

    test('only offices with a map position of their own name an area', () {
      Place named(String name) => directory.places.firstWhere((p) => p.name == name);
      expect(named('Kancharapalem').ownSpot, isTrue);
      expect(named('Gandhigram S.O (Visakhapatnam)').ownSpot, isFalse, reason: 'it only carries the head office point');
      expect(named('Visakhapatnam').ownSpot, isFalse, reason: 'shared with its sub offices');
      expect(named('Krishna Bazar').ownSpot, isFalse, reason: 'no position, only an estimate');
      expect(directory.nearestOwnSpot(17.735, 83.280)?.name, 'Kancharapalem');
      expect(directory.nearestOwnSpot(17.704, 83.297), isNull, reason: 'nothing of its own within 1.5 km of the city centre');
    });
  });

  group('one place from every way of choosing it', () {
    test('GPS: the map area first, then the nearest office of its own, else the town; the admin names apply', () async {
      final store = await demoStore();
      Future<PlacesIndex?> dir(double lat, double lng) async => directory;
      Future<OsmArea?> osm(double lat, double lng) async => const OsmArea(areas: ['Kancharapalem'], town: 'Visakhapatnam');
      Future<OsmArea?> offline(double lat, double lng) async => null;

      var place = await placeAtPoint(store, 17.735, 83.280, lookUp: osm, directory: dir);
      expect((place.area, place.town, place.pincode), ('Kancharapalem', 'Visakhapatnam', '530008'));

      place = await placeAtPoint(store, 17.735, 83.280, lookUp: offline, directory: dir);
      expect(place.area, 'Kancharapalem', reason: 'offline: the nearest office with a point of its own');

      place = await placeAtPoint(store, 17.704, 83.297, lookUp: offline, directory: dir);
      expect(place.area, 'Visakhapatnam', reason: 'no area name found: the town');

      store.catalog['settings'] = [const Entry(areaNamesId, {'renames': 'Gurudwara Junction = Gurudwara', 'blocked': 'Kancharapalem'})];
      Future<OsmArea?> both(double lat, double lng) async => const OsmArea(areas: ['Kancharapalem', 'Gurudwara Junction'], town: 'Visakhapatnam');
      place = await placeAtPoint(store, 17.735, 83.280, lookUp: both, directory: dir);
      expect(place.area, 'Gurudwara', reason: 'Kancharapalem blocked by the admin, Gurudwara Junction renamed');
      expect((place.latitude, place.longitude), (17.735, 83.280), reason: 'the GPS point itself is what the distance is measured from');
    });

    test('a place picked from the list, a typed pincode, a town', () async {
      final store = await demoStore();
      final kancharapalem = directory.places.firstWhere((p) => p.name == 'Kancharapalem');
      final picked = placeFromDirectory(store, kancharapalem);
      expect((picked.area, picked.town, picked.latitude), ('Kancharapalem', 'Visakhapatnam', 17.734));

      Future<PlacesIndex> byPin(String pin) async => directory;
      var place = await placeForPincode(store, '530008', directory: byPin);
      expect((place.area, place.town, place.latitude), ('Kancharapalem', 'Visakhapatnam', 17.734));
      place = await placeForPincode(store, '531116', directory: byPin);
      expect(place.area, 'Narsipatnam', reason: "a head office's pincode is the town's own; its sub office is not guessed");
      await expectLater(placeForPincode(store, '999999', directory: byPin), throwsStateError);
      await expectLater(placeForPincode(store, '12', directory: byPin), throwsStateError);

      final town = await placeForTown(store, 'Chintapalli', directory: () async => directory);
      expect((town.area, town.latitude), ('Chintapalli', 17.87));
    });

    test('saving: the area goes everywhere through placeName; the typed address is never the place', () async {
      final store = await demoStore();
      await store.setDeliveryAddress('Door 12-3, Main Road');
      await savePlace(store, const FoundPlace(latitude: 17.734, longitude: 83.279, area: 'Kancharapalem', town: 'Visakhapatnam', pincode: '530008'), followGps: true);
      expect((store.placeName, store.town, store.address, store.followsGps), ('Kancharapalem', 'Visakhapatnam', 'Door 12-3, Main Road', true));
      await store.setDeliveryAddress('Door 14');
      expect(store.placeName, 'Kancharapalem', reason: 'changing the delivery address keeps the place');
      await store.setLocation('530026', 'Door 14', lat: 17.691, lng: 83.204, town: 'Visakhapatnam');
      expect(store.area, isEmpty, reason: 'a new point without its area: the old area is not kept');
      expect(store.placeName, 'Visakhapatnam');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('area'), isEmpty);
    });
  });

  group('distance only', () {
    const shops = [
      Entry('near', {'name': 'Near', 'latitude': 17.735, 'longitude': 83.280}),
      Entry('far', {'name': 'Far', 'latitude': 17.667, 'longitude': 82.612}),
      Entry('nowhere', {'name': 'No location'}),
    ];
    const products = [
      Entry('p-near', {'name': 'Rice', 'price': 50, 'shopId': 'near', 'stock': 5}),
      Entry('p-far', {'name': 'Dal', 'price': 90, 'shopId': 'far', 'stock': 5}),
      Entry('p-none', {'name': 'Oil', 'price': 90, 'stock': 5}),
      Entry('p-nowhere', {'name': 'Salt', 'price': 20, 'shopId': 'nowhere', 'stock': 5}),
    ];

    test('the linked shop of an offer, an ad or a product', () {
      expect(linkedShopId(const Entry('a', {'shopId': 's1'})), 's1');
      expect(linkedShopId(const Entry('a', {'radiusShopId': 's2'})), 's2');
      expect(linkedShopId(const Entry('a', {'tapAction': 'shop', 'tapValue': 's3'})), 's3');
      expect(linkedShopId(const Entry('a', {'target': 'shop:s4'})), 's4');
      expect(linkedShopId(const Entry('a', {'target': 'category:x', 'locations': 'Narsipatnam'})), '', reason: 'a town list is not a shop');
    });

    test('shops, products and offers within the admin km of the customer; nothing before the place is known', () async {
      final store = await demoStore(shops: shops, products: products, settings: [const Entry('business', {'radiusKm': 10})]);
      expect(store.nearby().length, 3, reason: 'only the demo (no Firebase) with no place shows everything');
      final live = Store(live: true)..catalog = store.catalog;
      expect(live.nearby(), isEmpty, reason: 'the real app: nothing before the place is known');
      expect(live.visibleProducts(), isEmpty);
      expect(live.reaches(const Entry('offer', {'radiusShopId': 'near'})), isFalse);
      await savePlace(store, const FoundPlace(latitude: 17.734, longitude: 83.279, area: 'Kancharapalem', town: 'Visakhapatnam'));
      expect(store.nearby().map((s) => s.id), ['near']);
      expect(store.visibleProducts().map((p) => p.id), ['p-near'], reason: 'no product of a far shop, a shop without location, or no shop');
      expect(store.reaches(const Entry('offer', {'radiusShopId': 'near', 'radiusKm': 5})), isTrue);
      expect(store.reaches(const Entry('offer', {'radiusShopId': 'far', 'radiusKm': 100})), isFalse, reason: "an offer's own radius no longer counts");
      expect(store.reaches(const Entry('general', {'name': 'For everyone'})), isFalse, reason: 'an offer without a shop is shown to nobody');
      expect(store.visibleProducts(all: true).length, 4, reason: "the admin's preview shows everything");
      store.catalog['settings'] = [const Entry('business', {'radiusKm': 100})];
      expect(store.nearby().map((s) => s.id), ['near', 'far'], reason: "the admin's km decides");
    });

    test('the km falls back to 10 and stays sensible', () {
      expect(reachKmOf(const Entry('business', {})), 10);
      expect(reachKmOf(const Entry('business', {'radiusKm': 0})), 10);
      expect(reachKmOf(const Entry('business', {'radiusKm': 0.1})), .5);
      expect(reachKmOf(const Entry('business', {'radiusKm': 25})), 25);
    });
  });

  group('the first open asks for the location once', () {
    const place = FoundPlace(latitude: 17.734, longitude: 83.279, area: 'Kancharapalem', town: 'Visakhapatnam');
    Future<FoundPlace> atPoint(double lat, double lng) async => place;

    test('allowed: GPS sets the place and its area, no picker', () async {
      final store = await demoStore();
      var picked = 0;
      await askLocationOnFirstOpen(store, position: () async => fix(17.734, 83.279), atPoint: atPoint, pick: () async => picked++);
      expect((store.placeName, store.located, store.followsGps, picked), ('Kancharapalem', true, true, 0));
      await askLocationOnFirstOpen(store, position: () async => throw StateError('asked again'), atPoint: atPoint, pick: () async => picked++);
      expect(picked, 0, reason: 'asked once only');
    });

    test('refused or blocked: the picker opens straight away', () async {
      final store = await demoStore();
      var picked = 0;
      await askLocationOnFirstOpen(store, position: () async => null, atPoint: atPoint, pick: () async => picked++);
      expect((picked, store.located), (1, false));
    });

    test('a rough guess (a computer without GPS) is not used: the picker opens instead', () async {
      final store = await demoStore();
      var picked = 0;
      await askLocationOnFirstOpen(store, position: () async => fix(28.61, 77.21, accuracy: 30000), atPoint: atPoint, pick: () async => picked++);
      expect((picked, store.placeName), (1, ''), reason: 'no New Delhi from an internet guess');
    });
  });

  group('the greeting and the banner title', () {
    testWidgets('signed in: "Hello, <name>" with the area under it; otherwise "Hello, <area> People"', (tester) async {
      final store = await demoStore();
      await savePlace(store, const FoundPlace(latitude: 17.734, longitude: 83.279, area: 'Kancharapalem', town: 'Visakhapatnam'));
      ({String line, String under})? lines;
      Future<void> show() async {
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
          lines = greetingLines(context, store);
          return const SizedBox();
        })));
      }

      await show();
      expect((lines!.line, lines!.under), ('Hello, Kancharapalem People', ''));
      store.profileName = 'Ravi';
      await show();
      expect((lines!.line, lines!.under), ('Hello, Ravi', 'Kancharapalem'));
      final fresh = await demoStore();
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        lines = greetingLines(context, fresh);
        return const SizedBox();
      })));
      expect(lines!.line, 'Welcome', reason: 'no place yet: the welcome text');
    });

    testWidgets('the banner is always "Today\'s <area> Offers", never the admin\'s fixed text', (tester) async {
      final store = await demoStore(settings: [
        const Entry('notice', {'text': "Today's New Delhi Offers"}),
        const Entry('scrollingText', {'text': 'New Delhi'}),
      ]);
      await savePlace(store, const FoundPlace(latitude: 17.734, longitude: 83.279, area: 'Kancharapalem', town: 'Visakhapatnam'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HomeTickerSection(
            store: store,
            settings: store.entries('settings'),
            promotions: const [],
            products: const [Entry('p', {'name': 'Rice', 'price': 40, 'compareAtPrice': 50})],
            onProduct: (_) {},
          ),
        ),
      ));
      await tester.pump();
      expect(find.textContaining("Today's Kancharapalem Offers"), findsWidgets);
      expect(find.textContaining('New Delhi'), findsNothing);
    });
  });
}
