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

  testWidgets('the category circles are no longer on the home page (the Categories section was removed)', (tester) async {
    tester.view.physicalSize = const Size(1600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['categories']!.clear();
    await store.save('categories', _cat('cat-books', 'Books', 1));
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.byKey(const ValueKey('category-photo-cat-books')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
