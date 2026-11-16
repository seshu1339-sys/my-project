import 'dart:math';
import 'dart:typed_data';

import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/home_photo.dart';
import 'package:ecommerce_app/domain/item_shops.dart';
import 'package:ecommerce_app/services/photo_compress.dart';
import 'package:ecommerce_app/ui/item_shops_page.dart';
import 'package:ecommerce_app/ui/vendor_section_products.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// The vendor's own model photo for "Vendor photo compulsory" categories (owner, 16 Nov 2026).
class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    return {'status': 'approved', 'docId': 'p1'};
  }
}

const _categories = [
  Entry('cat-veg', {'name': 'Vegetables', 'active': true}),
  Entry('cat-plastic', {'name': 'Plastics', 'active': true, 'ownPhotoRequired': true}),
];
const _library = [
  Entry('lib-tomato', {'name': 'Tomato', 'categoryId': 'cat-veg', 'imageUrl': '', 'active': true}),
  Entry('lib-bucket', {'name': 'Bucket', 'categoryId': 'cat-plastic', 'imageUrl': '', 'active': true}),
];

void main() {
  test('a big phone photo is shrunk on the phone to under 100 KB, 800 px at most', () {
    final random = Random(7);
    final photo = img.Image(width: 3000, height: 2000);
    for (final p in photo) {
      p
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    }
    final big = Uint8List.fromList(img.encodeJpg(photo, quality: 95));
    expect(big.length, greaterThan(500 * 1024));
    final small = shrinkPhoto(big)!;
    expect(small.length, lessThanOrEqualTo(itemPhotoMaxBytes));
    final back = img.decodeJpg(small)!;
    expect(max(back.width, back.height), lessThanOrEqualTo(800));
    expect(shrinkPhoto(Uint8List.fromList([1, 2, 3])), isNull, reason: 'not a photo');
  });

  Future<_RecordingStore> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _RecordingStore();
    store.catalog['categories'] = _categories;
    store.catalog['productImageLibrary'] = _library;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: VendorAddProductSection(store: store, uid: 'v1', preview: (0, 2, true))))));
    return store;
  }

  Future<void> choose(WidgetTester tester, String category, String item) async {
    await tester.tap(find.byKey(const ValueKey('vendor-item-category-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(category).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('vendor-library-item-$item')));
    await tester.pumpAndSettle();
  }

  testWidgets('"Vendor photo compulsory" ON: the model photo step shows and Save stays off without a photo', (tester) async {
    final store = await pump(tester);
    await choose(tester, 'Plastics', 'lib-bucket');
    expect(find.byKey(const ValueKey('vendor-model-camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor-model-gallery')), findsOneWidget);
    expect(find.text(vendorModelPhotoNeeded), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('vendor-item-price')), '120');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('vendor-item-save'))).onPressed, isNull, reason: 'no photo, no Save');
    expect(store.calls, isEmpty);
  });

  testWidgets('OFF: no photo step, our catalog photo; the optional note (40 letters at most) is sent', (tester) async {
    final store = await pump(tester);
    await choose(tester, 'Vegetables', 'lib-tomato');
    expect(find.byKey(const ValueKey('vendor-model-camera')), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('vendor-item-note'))).maxLength, 40);
    await tester.enterText(find.byKey(const ValueKey('vendor-item-price')), '40');
    await tester.enterText(find.byKey(const ValueKey('vendor-item-note')), ' Desi ');
    await tester.tap(find.byKey(const ValueKey('vendor-item-save')));
    await tester.pumpAndSettle();
    expect(store.calls.single.$1, 'submitVendorChange');
    expect(store.calls.single.$2['changes'], {'libraryItemId': 'lib-tomato', 'unitType': 'kg', 'quantity': 1, 'price': 40.0, 'note': 'Desi'});
  });

  testWidgets("customer: each shop's row shows that vendor's own photo, the price, the note and the distance", (tester) async {
    const product = Entry('p1', {'name': 'Bucket', 'price': 120, 'unit': '1 pc', 'note': '20 litre, Milton', 'imageUrl': 'https://own/item_p1.jpg', 'libraryImageUrl': 'https://lib/bucket.jpg', 'ownPhoto': true});
    const offer = ItemOffer(product: product, shop: Entry('s1', {'name': 'Ravi Stores', 'imageUrl': 'https://shop/s1.jpg'}), price: 120, distanceKm: 1.2);
    expect(offer.itemPhoto, 'https://own/item_p1.jpg');
    expect(const ItemOffer(product: Entry('p2', {'libraryImageUrl': 'https://lib/b.jpg'}), shop: null, price: 1).itemPhoto, 'https://lib/b.jpg', reason: 'switch OFF: the catalog photo');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ItemOfferTile(offer: offer, onTap: () {}, now: () => DateTime(2026)))));
    expect(find.byKey(const ValueKey('item-offer-photo-p1')), findsOneWidget);
    expect(find.textContaining('20 litre, Milton'), findsOneWidget);
    expect(find.textContaining('₹120 for 1 pc'), findsOneWidget);
  });

  test('home: our catalog photo, never the vendor photo (an item not in the catalog keeps its own)', () {
    const own = Entry('p1', {'imageUrl': 'https://own/x.jpg', 'libraryImageUrl': 'https://lib/x.jpg', 'ownPhoto': true});
    expect(homePhoto(own).text('imageUrl'), 'https://lib/x.jpg');
    const custom = Entry('p2', {'imageUrl': 'https://own/y.jpg', 'libraryImageUrl': '', 'ownPhoto': true, 'customItem': true});
    expect(homePhoto(custom).text('imageUrl'), 'https://own/y.jpg');
    const plain = Entry('p3', {'imageUrl': 'https://lib/z.jpg', 'libraryImageUrl': 'https://lib/z.jpg'});
    expect(identical(homePhoto(plain), plain), isTrue);
  });
}
