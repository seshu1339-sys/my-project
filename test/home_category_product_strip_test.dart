import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/home_category_product_strip.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';
import 'package:ecommerce_app/ui/shared.dart';

void main() {
  Future<Store> openStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    return store;
  }

  ComponentLayout layoutFrom(Store store, BuildContext context) =>
      layoutFor(context, store.entries('settings'), 'crossSellStrip');

  testWidgets(
    'every card gets the same photo height from the shared main, and a card\'s own color override never changes another card',
    (tester) async {
      final store = await openStore();
      await store.save(
        'settings',
        const Entry('section_crossSellStrip', {
          'text': 'Fresh Fruits & Vegetables',
          'imageHeight': 90.0,
        }),
      );
      final apple = const Entry('p1', {
        'name': 'Apple',
        'categoryId': 'cat-fruits',
        'price': 10.0,
        'order': 0,
      });
      final carrot = const Entry('p2', {
        'name': 'Carrot',
        'categoryId': 'cat-vegetables',
        'price': 5.0,
        'order': 1,
        'backgroundColor': '#00ff00',
      });
      await store.save('products', apple);
      await store.save('products', carrot);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => HomeCategoryProductStrip(
                layout: layoutFrom(store, context),
                defaultTitle: 'Fresh Fruits & Vegetables',
                icon: Icons.eco_outlined,
                products: [apple, carrot],
                store: store,
                onProduct: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Fresh Fruits & Vegetables'), findsOneWidget);
      final arts = tester.widgetList<ProductArt>(find.byType(ProductArt));
      expect(
        arts.map((a) => a.height).toSet(),
        hasLength(1),
        reason: 'every card the same photo height, never a per-card field',
      );
      // The shared main's height is the least; a wide card gets a bigger photo so it never looks small.
      expect(arts.first.height, greaterThanOrEqualTo(90.0));

      // Apple (no override) keeps the default (no backgroundColor);
      // carrot's own backgroundColor override must not leak onto apple's
      // card.
      final appearances = tester
          .widgetList<ProductArt>(find.byType(ProductArt))
          .map((a) => a.appearance!);
      expect(
        appearances.map((a) => a.text('backgroundColor')).toList(),
        ['', '#00ff00'],
      );
    },
  );

  testWidgets('hides entirely when no vegetable/fruit products are passed', (
    tester,
  ) async {
    final store = await openStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => HomeCategoryProductStrip(
              layout: layoutFrom(store, context),
              defaultTitle: 'Fresh Fruits & Vegetables',
              icon: Icons.eco_outlined,
              products: const [],
              store: store,
              onProduct: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(HomeCategoryProductStrip), findsOneWidget);
    expect(find.text('Fresh Fruits & Vegetables'), findsNothing);
  });
}
