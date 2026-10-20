import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/element_groups.dart';

void main() {
  // store.init() seeds a full demo catalog (demo categories/promotions) --
  // cleared here so each test's own small, controlled set is the only
  // thing these group-ordering assertions have to reason about.
  Future<Store> openStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['categories'] = [];
    store.catalog['promotions'] = [];
    return store;
  }

  group('resolveSubKey / subNumberForKey', () {
    test('categories (group 16) resolve in stable order order', () async {
      final store = await openStore();
      await store.save(
        'categories',
        const Entry('catA', {'name': 'Vegetables', 'order': 0}),
      );
      await store.save(
        'categories',
        const Entry('catB', {'name': 'Fruits', 'order': 10}),
      );
      await store.save(
        'categories',
        const Entry('catC', {'name': 'Dairy', 'order': 20}),
      );

      expect(resolveSubKey(store, 16, 1), 'category-catA');
      expect(resolveSubKey(store, 16, 2), 'category-catB');
      expect(resolveSubKey(store, 16, 3), 'category-catC');
      expect(
        resolveSubKey(store, 16, 4),
        isNull,
        reason: 'only 3 categories exist',
      );
    });

    test(
      'adding a new category never shifts the sub-numbers of the existing ones',
      () async {
        final store = await openStore();
        await store.save(
          'categories',
          const Entry('catA', {'name': 'Vegetables', 'order': 0}),
        );
        await store.save(
          'categories',
          const Entry('catB', {'name': 'Fruits', 'order': 10}),
        );
        expect(resolveSubKey(store, 16, 1), 'category-catA');
        expect(resolveSubKey(store, 16, 2), 'category-catB');

        // A brand new category, added after the others (higher order) --
        // must get the NEXT sub-number, and the first two must be unchanged.
        await store.save(
          'categories',
          const Entry('catNew', {'name': 'Bakery', 'order': 20}),
        );
        expect(resolveSubKey(store, 16, 1), 'category-catA');
        expect(resolveSubKey(store, 16, 2), 'category-catB');
        expect(resolveSubKey(store, 16, 3), 'category-catNew');
      },
    );

    test('ads (24) and boxes (25) are disambiguated by placement despite sharing the promo- prefix', () async {
      final store = await openStore();
      await store.save(
        'promotions',
        const Entry('ad1', {'placement': 'ad', 'order': 0}),
      );
      await store.save(
        'promotions',
        const Entry('box1', {'placement': 'box', 'order': 0}),
      );
      await store.save(
        'promotions',
        const Entry('slide1', {'placement': 'carousel', 'order': 0}),
      );

      expect(resolveSubKey(store, 24, 1), 'promo-ad1');
      expect(resolveSubKey(store, 25, 1), 'promo-box1');
      expect(resolveSubKey(store, 15, 1), 'promo-slide1');
      expect(resolveSubKey(store, 24, 2), isNull);
    });

    test('subNumberForKey is the exact inverse of resolveSubKey', () async {
      final store = await openStore();
      await store.save(
        'promotions',
        const Entry('adX', {'placement': 'ad', 'order': 0}),
      );
      await store.save(
        'promotions',
        const Entry('adY', {'placement': 'ad', 'order': 10}),
      );

      expect(subNumberForKey(store, 'promo-adY'), (24, 2));
    });
  });

  group('isGroupSubKey / groupSubEntry', () {
    test(
      'recognizes every group prefix and resolves the right entry',
      () async {
        final store = await openStore();
        await store.save(
          'categories',
          const Entry('catA', {'name': 'Vegetables'}),
        );

        expect(isGroupSubKey('category-catA'), isTrue);
        expect(isGroupSubKey('promo-ad1'), isTrue);
        expect(isGroupSubKey('logo'), isFalse);
        expect(
          groupSubEntry(store, 'category-catA').text('name'),
          'Vegetables',
        );
      },
    );
  });
}
