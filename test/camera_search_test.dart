import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/camera_search.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/services/usage.dart';
import 'package:ecommerce_app/ui/admin_camera_search.dart';
import 'package:ecommerce_app/ui/category_page.dart';
import 'package:ecommerce_app/ui/item_shops_page.dart';
import 'package:ecommerce_app/ui/storefront.dart';

// Camera search (cost cuts part 1, 18 Nov 2026): the phone's ML Kit labels -> one item, a category, or every category button. No AI
// unless the admin allows it; only counts are kept.
const categories = [
  Entry('cat-vegetables', {'name': 'Fresh & Vegetables', 'active': true}),
  Entry('cat-fruits', {'name': 'Fruits'}),
  Entry('cat-plastics', {'name': 'Plastics', 'parentId': ''}),
  Entry('cat-fancy', {'name': 'Fancy'}),
  Entry('cat-clothes', {'name': 'Clothes'}),
  Entry('cat-grocery-staples', {'name': 'Grocery & Staples'}),
  Entry('cat-rice-dal-grains', {'name': 'Rice, Dal & Grains'}),
  Entry('cat-old', {'name': 'Old shelf', 'active': false}),
];
const items = [
  Entry('lib-onion', {'name': 'Onion', 'tags': 'ఉల్లిపాయ', 'categoryId': 'cat-vegetables', 'active': true}),
  Entry('lib-tomato', {'name': 'Tomato', 'tags': 'టమాటా', 'categoryId': 'cat-vegetables', 'active': true}),
  Entry('lib-banana', {'name': 'Banana', 'tags': 'అరటి పండు', 'categoryId': 'cat-fruits', 'active': true}),
  Entry('lib-red-onion', {'name': 'Red Onion', 'tags': 'onion', 'categoryId': 'cat-vegetables', 'active': true}),
  Entry('lib-off', {'name': 'Mango', 'categoryId': 'cat-fruits', 'active': false}),
];

CameraMatch match(List<CameraLabel> labels, {List<CameraRow> rows = defaultCameraRows}) =>
    matchCameraLabels(labels, rows: rows, items: items, categories: categories);

void main() {
  group('matching the phone labels', () {
    test('an exact item name opens that item', () {
      final m = match(const [CameraLabel('Tomato', 0.9), CameraLabel('Vegetable', 0.95)]);
      expect(m.kind, CameraMatchKind.item);
      expect(m.itemId, 'lib-tomato');
      expect(m.itemName, 'Tomato');
      expect(m.label, 'Tomato');
    });

    test('a Telugu or other word in the item tags also finds the item', () {
      expect(match(const [CameraLabel('టమాటా', 0.8)]).itemId, 'lib-tomato');
    });

    test('two items for one label open their common category', () {
      final m = match(const [CameraLabel('Onion', 0.8)]);
      expect(m.kind, CameraMatchKind.category);
      expect(m.categoryId, 'cat-vegetables');
    });

    test('the owner table sends each label to its category', () {
      expect(match(const [CameraLabel('Vegetable', 0.9)]).categoryId, 'cat-vegetables');
      expect(match(const [CameraLabel('Leaf vegetable', 0.9)]).categoryId, 'cat-vegetables');
      expect(match(const [CameraLabel('Fruit', 0.7)]).categoryId, 'cat-fruits');
      expect(match(const [CameraLabel('Bucket', 0.8)]).categoryId, 'cat-plastics');
      expect(match(const [CameraLabel('Bangle', 0.8)]).categoryId, 'cat-fancy');
      expect(match(const [CameraLabel('Jewellery', 0.8)]).categoryId, 'cat-fancy');
      expect(match(const [CameraLabel('Shirt', 0.8)]).categoryId, 'cat-clothes');
      expect(match(const [CameraLabel('Sari', 0.8)]).categoryId, 'cat-clothes');
      expect(match(const [CameraLabel('Clothing', 0.8)]).categoryId, 'cat-clothes');
      // The table wins over a category name: rice is Kirana (Grocery & Staples), not "Rice, Dal & Grains".
      expect(match(const [CameraLabel('Rice', 0.8)]).categoryId, 'cat-grocery-staples');
      expect(match(const [CameraLabel('Packaged goods', 0.8)]).categoryId, 'cat-grocery-staples');
    });

    test('a category name works without a table row (plural and singular)', () {
      expect(match(const [CameraLabel('Fruits', 0.8)], rows: const []).categoryId, 'cat-fruits');
      expect(match(const [CameraLabel('Vegetable', 0.8)], rows: const []).categoryId, 'cat-vegetables');
      expect(match(const [CameraLabel('Grain', 0.8)], rows: const []).categoryId, 'cat-rice-dal-grains');
    });

    test('the labels together decide the category', () {
      final m = match(const [CameraLabel('Shirt', 0.6), CameraLabel('Fruit', 0.7), CameraLabel('Textile', 0.6)]);
      expect(m.categoryId, 'cat-clothes');
    });

    test('a table row can point a label to one item', () {
      final m = match(const [CameraLabel('Plantain', 0.8)], rows: const [CameraRow('plantain', itemId: 'lib-banana')]);
      expect(m.kind, CameraMatchKind.item);
      expect(m.itemId, 'lib-banana');
    });

    test('nothing matches: none (every category button shows)', () {
      expect(match(const [CameraLabel('Sky', 0.9), CameraLabel('Cloud', 0.8)]).kind, CameraMatchKind.none);
      expect(match(const []).kind, CameraMatchKind.none);
    });

    test('unsure labels, switched-off items and switched-off categories are not used', () {
      expect(match(const [CameraLabel('Tomato', 0.4)]).kind, CameraMatchKind.none);
      expect(match(const [CameraLabel('Mango', 0.9)]).kind, CameraMatchKind.none);
      expect(match(const [CameraLabel('Shelf', 0.9)], rows: const [CameraRow('shelf', categoryId: 'cat-old')]).kind, CameraMatchKind.none);
    });

    test('the table and the AI switch come from settings/cameraSearch', () {
      expect(cameraRowsOf(null), defaultCameraRows);
      expect(cameraAiAllowed(null), isFalse);
      const saved = Entry('cameraSearch', {
        'aiAllowed': true,
        'rows': [
          {'label': 'pot', 'categoryId': 'cat-plastics', 'itemId': ''},
          {'label': '', 'categoryId': 'cat-fancy'},
          {'label': 'nothing'},
        ],
      });
      expect([for (final r in cameraRowsOf(saved)) r.label], ['pot']);
      expect(cameraAiAllowed(saved), isTrue);
      expect(cameraAiAllowed(const Entry('cameraSearch', {'aiAllowed': 'yes'})), isFalse);
      expect(cameraRowsOf(const Entry('cameraSearch', {'rows': []})), isEmpty);
    });

    test('the count key is label|what opened', () {
      expect(cameraUsageKey('Vegetable', 'category:cat-vegetables'), 'vegetable|category:cat-vegetables');
      expect(cameraUsageKey('', 'none'), '-|none');
    });
  });

  group('the camera button in the app', () {
    late Store store;
    final counted = <String>[];
    void sink(String event, Map<String, String> params) {
      if (event == 'camera_label') counted.add(params['key'] ?? '');
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = Store();
      await store.init();
      store.catalog['categories'] = [...categories];
      store.catalog['productImageLibrary'] = [...items];
      counted.clear();
      Usage.sinks.add(sink);
    });
    tearDown(() => Usage.sinks.remove(sink));

    Future<void> open(WidgetTester tester, List<CameraLabel> labels, {String? path = 'photo.jpg'}) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Storefront(store: store, takePhoto: () async => path, cameraLabeler: (_) async => labels)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Camera search').first);
      await tester.pumpAndSettle();
    }

    testWidgets('a matched item opens its shops', (tester) async {
      await open(tester, const [CameraLabel('Banana', 0.9)]);
      expect(find.byType(ItemShopsPage), findsOneWidget);
      expect(counted, ['banana|item:Banana']);
    });

    testWidgets('a matched category opens that category', (tester) async {
      await open(tester, const [CameraLabel('Bucket', 0.9)]);
      final page = tester.widget<CategoryPage>(find.byType(CategoryPage));
      expect(page.categoryId, 'cat-plastics');
      expect(counted, ['bucket|category:cat-plastics']);
    });

    testWidgets('nothing matched: every category button, and the choice is counted', (tester) async {
      await open(tester, const [CameraLabel('Sky', 0.9)]);
      expect(find.byKey(const ValueKey('camera-categories')), findsOneWidget);
      expect(find.byKey(const ValueKey('camera-category-cat-old')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('camera-category-cat-fruits')));
      await tester.pumpAndSettle();
      expect(tester.widget<CategoryPage>(find.byType(CategoryPage)).categoryId, 'cat-fruits');
      expect(counted, ['sky|chose:cat-fruits']);
    });

    testWidgets('the phone could not label the photo: the category buttons show (no AI while the switch is off)', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Storefront(store: store, takePhoto: () async => 'photo.jpg', cameraLabeler: (_) async => throw UnsupportedError('no ML Kit')),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Camera search').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('camera-categories')), findsOneWidget);
    });

    testWidgets('cancelling the camera does nothing', (tester) async {
      await open(tester, const [CameraLabel('Banana', 0.9)], path: null);
      expect(find.byType(ItemShopsPage), findsNothing);
      expect(find.byKey(const ValueKey('camera-categories')), findsNothing);
      expect(counted, isEmpty);
    });
  });

  group('Settings > Camera search', () {
    testWidgets('shows the starting table, saves the AI switch and the rows, and lists the counts', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      store.catalog['categories'] = [...categories];
      store.catalog['productImageLibrary'] = [...items];
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminCameraSearchPage(
            store: store,
            loadDays: () async => [
              {
                'keys': {
                  'a': {'key': 'sky|none', 'count': 3},
                  'b': {'key': 'vegetable|category:cat-vegetables', 'count': 5},
                },
              },
              {
                'keys': {'c': {'key': 'sky|none', 'count': 2}},
              },
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('camera-row-${defaultCameraRows.length - 1}')), findsOneWidget);
      final ai = tester.widget<SwitchListTile>(find.byKey(const ValueKey('camera-ai-switch')));
      expect(ai.value, isFalse);
      expect(find.text('vegetable → opened Fresh & Vegetables'), findsOneWidget);
      expect(find.text('sky → nothing matched, they chose nothing'), findsOneWidget);
      expect(find.text('5'), findsNWidgets(2)); // sky 3 + 2, vegetable 5

      await tester.tap(find.byKey(const ValueKey('camera-ai-switch')));
      await tester.tap(find.text('Add to table'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('camera-save')));
      await tester.pumpAndSettle();
      // The new "sky" row has no category yet: not saved.
      expect(cameraSettingsOf(store.entries('settings')), isNull);

      final added = find.byKey(ValueKey('camera-row-${defaultCameraRows.length}'));
      expect(find.descendant(of: added, matching: find.text('sky')), findsOneWidget);
      await tester.ensureVisible(added);
      await tester.tap(find.descendant(of: added, matching: find.byTooltip('Remove row')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('camera-save')));
      await tester.pumpAndSettle();
      final saved = cameraSettingsOf(store.entries('settings'));
      expect(cameraAiAllowed(saved), isTrue);
      expect(cameraRowsOf(saved).length, defaultCameraRows.length);
      expect(cameraRowsOf(saved).first.categoryId, 'cat-plastics');
    });

    test('counts add up across days', () {
      final counts = cameraCountsOf([
        {'keys': {'a': {'key': 'sky|none', 'count': 3}}},
        {'keys': {'a': {'key': 'sky|none', 'count': 2}, 'b': {'key': 'bad', 'count': 9}}},
      ]);
      expect(counts.single.label, 'sky');
      expect(counts.single.opened, 'none');
      expect(counts.single.count, 5);
    });
  });
}
