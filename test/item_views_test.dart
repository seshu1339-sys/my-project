import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/details.dart';

class ViewStore extends Store {
  int views = 0;
  @override
  Future<void> trackItemView(Entry entry) async {
    views++;
  }
}

void main() {
  testWidgets('item view is recorded once per visit, not on cart rebuilds', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = ViewStore();
    await store.init();
    final product = store.entries('products').first;
    await tester.pumpWidget(
      MaterialApp(
        home: ProductPage(store: store, entry: product),
      ),
    );
    expect(store.views, 1);
    store.add(product);
    await tester.pump();
    expect(store.views, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: ProductPage(store: store, entry: product),
      ),
    );
    expect(store.views, 2);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
