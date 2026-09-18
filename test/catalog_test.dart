import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/services/search.dart';

void main() {
  test('location pricing falls back to base price', () {
    const entry = Entry('one', {
      'price': 100,
      'prices': {'560001': 80},
    });
    expect(entry.price('560001'), 80);
    expect(entry.price('999999'), 100);
  });
  test('text() falls back for a missing key and an explicit empty string alike', () {
    const entry = Entry('one', {'unit': ''});
    expect(entry.text('unit', 'each'), 'each');
    expect(entry.text('name', 'Unnamed'), 'Unnamed');
    const named = Entry('two', {'unit': 'kg'});
    expect(named.text('unit', 'each'), 'kg');
  });
  test('scheduling uses an inclusive start and exclusive end', () {
    const entry = Entry('one', {
      'startsAt': '2026-09-14T10:00:00Z',
      'endsAt': '2026-09-14T11:00:00Z',
    });
    expect(entry.visibleAt(DateTime.parse('2026-09-14T09:59:59Z')), false);
    expect(entry.visibleAt(DateTime.parse('2026-09-14T10:00:00Z')), true);
    expect(entry.visibleAt(DateTime.parse('2026-09-14T11:00:00Z')), false);
  });
  test('distance calculation and multiword search', () {
    expect(distanceKm(12.9716, 77.5946, 12.9716, 77.5946), 0);
    expect(distanceKm(0, 0, 0, 1), closeTo(111.195, .01));
    expect(
      const SmartSearch()
          .text(demoCatalog()['products']!, 'local electrical')
          .single
          .id,
      'p5',
    );
  });
  test(
    'cart enforces stock, reprices by pincode and demo edits persist',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await store.save(
        'products',
        const Entry('p0', {
          'name': 'Test',
          'price': 100,
          'prices': {'560001': 80},
          'stock': 2,
        }),
      );
      final p = store.product('p0')!;
      store.add(p);
      store.add(p);
      store.add(p);
      expect(store.count, 2);
      expect(store.total, 200);
      await store.setLocation('560001', 'Bengaluru');
      expect(store.total, 160);
      store.add(p, -1);
      expect(store.count, 1);
      final restored = Store();
      await restored.init();
      expect(restored.product('p0')!.text('name'), 'Test');
      store.dispose();
      restored.dispose();
    },
  );
  test('nearby shops respects pincode or GPS radius', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    expect(store.nearby(), isEmpty);
    await store.setLocation('560001', '');
    expect(store.nearby().single.id, 's1');
    await store.setLocation('', '', lat: 0, lng: 0);
    expect(store.nearby(), isEmpty);
    store.dispose();
  });
}
