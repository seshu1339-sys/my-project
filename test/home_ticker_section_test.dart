import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/home_ticker_section.dart';

void main() {
  Future<Store> openStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    return store;
  }

  testWidgets(
    "the label's font size/weight and the strip's border follow settings/section_notice, not hardcoded defaults",
    (tester) async {
      final store = await openStore();
      await store.save('products', const Entry('p1', {
        'name': 'Discounted Thing',
        'price': 50.0,
        'compareAtPrice': 100.0,
        'active': true,
      }));
      await store.save('settings', const Entry('section_notice', {
        'fontSize': 20.0,
        'fontWeight': 700.0,
        'borderColor': '#ff0000',
        'borderWidth': 4.0,
      }));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeTickerSection(
        store: store,
        settings: store.entries('settings'),
        promotions: const [],
        products: store.entries('products'),
        onProduct: (_) {},
      ))));
      await tester.pump();

      final label = tester.widget<Text>(
        find.textContaining("Today's Best Offers in", findRichText: false),
      );
      expect(label.style?.fontSize, 20.0, reason: 'label must use the admin-set font size, not a hardcoded 13');
      expect(label.style?.fontWeight, FontWeight.w700);

      // the strip draws the border, once (the outer section box leaves it to the strip)
      final bordered = tester.widgetList<Container>(find.byType(Container)).where((c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).border != null);
      expect(bordered.length, 1, reason: 'borderColor/borderWidth must actually draw a border, and only one');
    },
  );
}
