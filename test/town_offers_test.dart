// Location-based offers: the town rules themselves, then the real customer
// page (MarketApp) switching offers, ads and the ticker's town name, and the
// admin Content "Location" field.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/towns.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/entry_editor.dart';
import 'package:ecommerce_app/ui/location_picker_dialog.dart';
import 'places_fixture.dart';

Entry _promo(String id, String placement, {String locations = ''}) => Entry(
  id,
  {
    'name': id,
    'placement': placement,
    'locations': locations,
    'active': true,
    'order': 0,
  },
);

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
      expect(ids(''), ['narsi', 'anak', 'everyone']); // no town yet: all
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
    testWidgets('offers, ads and the ticker follow the chosen town', (
      tester,
    ) async {
      await _wide(tester);
      final store = await _store(
        promotions: [
          _promo('Narsipatnam special', 'carousel', locations: 'Narsipatnam'),
          _promo('Anakapalle special', 'carousel', locations: 'Anakapalle'),
          _promo('Narsipatnam ad', 'ad', locations: 'Narsipatnam'),
          _promo('Anakapalle ad', 'ad', locations: 'Anakapalle'),
          _promo('Everyone ad', 'ad'),
        ],
      );
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();

      await store.setLocation('', '', town: 'Narsipatnam');
      await tester.pump();
      expect(find.text("Today's Narsipatnam Offers"), findsOneWidget);
      expect(find.text('Narsipatnam special'), findsWidgets);
      expect(find.text('Anakapalle special'), findsNothing);
      expect(find.text('Narsipatnam ad'), findsWidgets);
      expect(find.text('Anakapalle ad'), findsNothing);
      expect(find.text('Everyone ad'), findsNothing);

      // Changing the location changes the name and the offers at once.
      await store.setLocation('', '', town: 'Anakapalle');
      await tester.pump();
      expect(find.text("Today's Anakapalle Offers"), findsOneWidget);
      expect(find.text("Today's Narsipatnam Offers"), findsNothing);
      expect(find.text('Anakapalle special'), findsWidgets);
      expect(find.text('Narsipatnam special'), findsNothing);
      expect(find.text('Anakapalle ad'), findsWidgets);
      expect(find.text('Narsipatnam ad'), findsNothing);

      // A town with no offers of its own falls back to the general ones.
      await store.setLocation('', '', town: 'Visakhapatnam');
      await tester.pump();
      expect(find.text("Today's Visakhapatnam Offers"), findsOneWidget);
      expect(find.text('Everyone ad'), findsWidgets);
      expect(find.text('Narsipatnam ad'), findsNothing);
      // ...and with no general offers either, a message, never empty boxes.
      expect(find.byKey(const ValueKey('no-offers-notice')), findsOneWidget);
      expect(
        find.text('No offers in Visakhapatnam yet. Check back soon!'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('a town with no offers shows the admin\'s own message', (
      tester,
    ) async {
      await _wide(tester);
      final store = await _store(
        business: {'noOffersMessage': 'Nothing in {town} today'},
        promotions: [_promo('Narsipatnam special', 'carousel', locations: 'Narsipatnam')],
      );
      await tester.pumpWidget(MarketApp(store: store));
      await store.setLocation('', '', town: 'Anakapalle');
      await tester.pump();
      expect(find.text('Nothing in Anakapalle today'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('with no town chosen every offer still shows', (tester) async {
      await _wide(tester);
      final store = await _store(
        promotions: [_promo('Narsipatnam special', 'carousel', locations: 'Narsipatnam')],
      );
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      expect(find.text('Narsipatnam special'), findsWidgets);
      expect(find.byKey(const ValueKey('no-offers-notice')), findsNothing);
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

  group('admin content', () {
    testWidgets('an offer\'s Location is chosen from the towns and saved', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store();
      await tester.pumpWidget(
        MaterialApp(
          home: EntryEditor(store: store, collection: 'promotions'),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Headline / ticker text'),
        'Diwali sale',
      );
      for (final town in ['Narsipatnam', 'Anakapalle']) {
        final chip = find.byKey(ValueKey('location-chip-$town'));
        expect(chip, findsOneWidget);
        tester.widget<FilterChip>(chip).onSelected!(true);
        await tester.pump();
      }
      await tester.scrollUntilVisible(
        find.text('Save changes'),
        300,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final saved = store
          .entries('promotions')
          .firstWhere((e) => e.text('name') == 'Diwali sale');
      expect(saved.text('locations'), 'Narsipatnam, Anakapalle');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });
}
