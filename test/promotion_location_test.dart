// Who sees an offer on the real customer page (MarketApp): distance only (owner, 11 Nov 2026). Only customers within the admin's km
// (Business Profile) of the offer's shop see it; an old pincode or area target no longer decides, and an offer without a shop is
// shown to nobody once the customer's place is known.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';

void main() {
  testWidgets('an offer shows only within the km of its shop, whatever its old pincode or area target; no shop: nobody', (tester) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    // The demo catalog seeds its own sample carousel entries; clear them so these are the only ones.
    store.catalog['promotions']?.clear();
    store.catalog['shops'] = [
      const Entry('kancharapalem-shop', {'name': 'Kancharapalem Kirana', 'latitude': 17.735, 'longitude': 83.280}),
    ];
    store.catalog['settings'] = [...store.entries('settings').where((e) => e.id != 'business'), Entry('business', {...store.business.data, 'radiusKm': 10})];
    await store.save('promotions', const Entry('near', {
      'name': 'Near shop offer',
      'placement': 'carousel',
      'radiusShopId': 'kancharapalem-shop',
      // Old targets, kept in the record and no longer used.
      'targetPincode': '560001',
      'geoShape': 'rectangle',
      'targetRectangle': {'north': 13.0, 'south': 12.9, 'east': 77.7, 'west': 77.5},
    }));
    await store.save('promotions', const Entry('general', {'name': 'For everyone', 'placement': 'carousel'}));
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();

    // Narsipatnam, about 70 km away.
    await store.setLocation('531116', '', lat: 17.667, lng: 82.612, town: 'Narsipatnam');
    await tester.pump();
    expect(find.text('Near shop offer'), findsNothing);
    expect(find.text('For everyone'), findsNothing);

    // Kancharapalem, next to the shop.
    await store.setLocation('530008', '', lat: 17.734, lng: 83.279, town: 'Visakhapatnam', area: 'Kancharapalem');
    await tester.pump();
    expect(find.text('Near shop offer'), findsWidgets);
    expect(find.text('For everyone'), findsNothing, reason: 'an offer without a shop is shown to nobody');

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
