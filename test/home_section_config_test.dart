import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/home_section_config.dart';

void main() {
  group('home_section_config', () {
    test('sectionConfig finds by id, falls back to an empty Entry', () {
      final settings = [const Entry('section_popular', {'height': 5})];
      expect(sectionConfig(settings, 'popular').number('height', 0), 5);
      expect(sectionConfig(settings, 'missing').id, '');
    });

    test('sectionVisible defaults true, false only when explicitly "false"', () {
      expect(sectionVisible(const Entry('', {})), isTrue);
      expect(sectionVisible(const Entry('x', {'visible': 'false'})), isFalse);
      expect(sectionVisible(const Entry('x', {'visible': 'true'})), isTrue);
      expect(sectionVisible(const Entry('x', {'visible': false, 'active': true})), isFalse);
    });

    test('sectionOrder falls back to the built-in default order, then to 999', () {
      expect(sectionOrder(const [], 'categories'), 30.0);
      expect(sectionOrder(const [], 'promo'), 20.0);
      expect(sectionOrder(const [], 'not-a-real-section'), 999);
    });

    test('sectionOrder prefers a stored order value over the default', () {
      final settings = [const Entry('section_categories', {'order': 5.0})];
      expect(sectionOrder(settings, 'categories'), 5.0);
    });

    test('reorderableHomeSections lists exactly the 3 reorderable sections (Categories was removed from the home page)', () {
      expect(reorderableHomeSections.map((d) => d.key).toList(),
          ['promo', 'popular', 'localServices']);
    });

    test('adjustSectionField/adjustSectionHeight write through to a bare Store', () async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await adjustSectionHeight(store, 'popular', 240);
      expect(sectionConfig(store.entries('settings'), 'popular').number('height', 0), 240);
      await adjustSectionField(store, 'popular', 'order', 15.0);
      expect(sectionConfig(store.entries('settings'), 'popular').number('order', 0), 15.0);
      // Writing one field must not clobber another already-saved field.
      expect(sectionConfig(store.entries('settings'), 'popular').number('height', 0), 240);
      store.dispose();
    });

    test('reorderHomeSections re-stamps order for every reorderable section from its new position', () async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      final before = [...reorderableHomeSections]
        ..sort((a, b) => sectionOrder(store.entries('settings'), a.key)
            .compareTo(sectionOrder(store.entries('settings'), b.key)));
      final oldIndex = before.indexWhere((d) => d.key == 'localServices');
      await reorderHomeSections(store, oldIndex, 0);
      expect(
        sectionOrder(store.entries('settings'), 'localServices'),
        lessThan(sectionOrder(store.entries('settings'), 'promo')),
      );
      store.dispose();
    });
  });
}
