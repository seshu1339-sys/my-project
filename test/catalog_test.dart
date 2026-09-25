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
  test('search indexes product names and category/subcategory names, including nested ones', () {
    const categories = [
      Entry('home', {'name': 'Home & living', 'parentId': ''}),
      Entry('kitchen', {'name': 'Kitchen', 'parentId': 'home'}),
      Entry('mugs', {'name': 'Mugs & cups', 'parentId': 'kitchen'}),
      Entry('electronics', {'name': 'Electronics', 'parentId': ''}),
    ];
    const products = [
      Entry('p1', {'name': 'Ceramic mug', 'categoryId': 'mugs'}),
      Entry('p2', {'name': 'Wireless headphones', 'categoryId': 'electronics'}),
    ];
    const search = SmartSearch();
    // A few letters of the product's own name.
    expect(search.text(products, 'cera', categories).single.id, 'p1');
    // The product's direct (leaf) subcategory name.
    expect(search.text(products, 'mugs', categories).single.id, 'p1');
    // A grandparent category name still finds the product nested two levels below it.
    expect(search.text(products, 'home', categories).single.id, 'p1');
    // Case-insensitive, partial, and does not also match the unrelated product.
    final byParent = search.text(products, 'KITCH', categories);
    expect(byParent.map((e) => e.id), ['p1']);
    // No categories passed at all still degrades to plain name/description/tags matching.
    expect(search.text(products, 'wireless').single.id, 'p2');
    // A malformed/self-referential parentId chain must not hang or crash search.
    const cyclic = [
      Entry('a', {'name': 'Loop A', 'parentId': 'b'}),
      Entry('b', {'name': 'Loop B', 'parentId': 'a'}),
    ];
    const cyclicProducts = [Entry('p3', {'name': 'Cyclic product', 'categoryId': 'a'})];
    expect(search.text(cyclicProducts, 'loop a', cyclic).single.id, 'p3');
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
