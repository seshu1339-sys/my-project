// The built-in category photos: which categories get one, that the files ship
// with the app, and that the home page's category circles show them -- all the
// same size -- while a photo set by the admin still wins.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/category_images.dart';
import 'package:ecommerce_app/main.dart';

Entry _cat(String id, String name, int order, {String image = ''}) =>
    Entry(id, {'name': name, 'order': order, 'active': true, 'imageUrl': image});

void main() {
  group('which categories get a built-in photo', () {
    test('by id or by name, ignoring case and punctuation', () {
      String? of(String id, String name) =>
          builtInCategoryImage(Entry(id, {'name': name}));
      expect(of('cat-electronics', 'Electronics'), 'assets/category_icons/electronics.webp');
      expect(of('abc123', 'Footwear'), 'assets/category_icons/footwear.webp');
      expect(of('cat-books', 'Anything'), 'assets/category_icons/books.webp');
      expect(of('x', ' Mobiles '), 'assets/category_icons/mobiles.webp');
      expect(of('x', 'FANCY'), 'assets/category_icons/fancy.webp');
      expect(of('cat-fruits', 'Fruits'), isNull);
      expect(of('cat-fashion', 'Fashion'), isNull);
      expect(of('x', ''), isNull);
    });

    test('all eight photos ship in assets/category_icons and are small', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/category_icons/'));
      for (final slug in builtInCategorySlugs) {
        final file = File('assets/category_icons/$slug.webp');
        expect(file.existsSync(), isTrue, reason: slug);
        expect(file.lengthSync(), lessThan(100 * 1024), reason: '$slug should be light');
      }
      expect(builtInCategorySlugs.length, 8);
    });
  });

  group('home page category circles', () {
    Future<Store> storeWith(List<Entry> categories) async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      store.catalog['categories']!.clear();
      for (final category in categories) {
        await store.save('categories', category);
      }
      return store;
    }

    testWidgets('each category shows its own photo, every circle the same size', (tester) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await storeWith([
        _cat('cat-fruits', 'Fruits', 1),
        for (final (i, name) in ['Books', 'Clothes', 'Electricals', 'Electronics', 'Fancy', 'Footwear', 'Mobiles', 'Plastics'].indexed)
          _cat('cat-${name.toLowerCase()}', name, 2 + i),
      ]);
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      final sizes = <String, Size>{};
      for (final name in ['books', 'clothes', 'electricals', 'electronics', 'fancy', 'footwear', 'mobiles', 'plastics']) {
        final finder = find.byKey(ValueKey('category-photo-cat-$name'));
        expect(finder, findsOneWidget, reason: '$name photo');
        final image = tester.widget<Image>(finder);
        expect(image.image, isA<AssetImage>());
        expect((image.image as AssetImage).assetName, 'assets/category_icons/$name.webp');
        sizes[name] = tester.getSize(finder);
      }
      // A category without a photo keeps its icon, in a circle of the same size.
      expect(find.byKey(const ValueKey('category-photo-cat-fruits')), findsNothing);
      expect(sizes.values.toSet(), hasLength(1), reason: 'circle sizes: $sizes');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('a photo the admin sets replaces the built-in one; clearing it brings it back', (tester) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await storeWith([_cat('cat-books', 'Books', 1), _cat('cat-fancy', 'Fancy', 2)]);
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      Finder photo(String id) => find.byKey(ValueKey('category-photo-$id'));
      expect(tester.widget<Image>(photo('cat-books')).image, isA<AssetImage>());
      final before = tester.getSize(photo('cat-books'));

      await store.save('categories', _cat('cat-books', 'Books', 1, image: 'https://example.com/my-books.png'));
      await tester.pump();
      final custom = tester.widget<Image>(photo('cat-books')).image;
      expect(custom, isA<NetworkImage>());
      expect((custom as NetworkImage).url, 'https://example.com/my-books.png');
      expect(tester.getSize(photo('cat-books')), before, reason: 'same circle size with the admin photo');
      expect(tester.widget<Image>(photo('cat-fancy')).image, isA<AssetImage>(), reason: 'others unaffected');

      await store.save('categories', _cat('cat-books', 'Books', 1));
      await tester.pump();
      expect(tester.widget<Image>(photo('cat-books')).image, isA<AssetImage>());
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });
}
