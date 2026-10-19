import 'package:flutter/material.dart';

import '../data/store.dart';
import 'layout_settings.dart';
import 'product_page.dart';
import 'shared.dart';

class CategoryPage extends StatelessWidget {
  const CategoryPage({
    super.key,
    required this.store,
    required this.categoryId,
  });
  final Store store;
  final String categoryId;

  @override
  Widget build(BuildContext context) {
    final category = store
        .entries('categories')
        .where((item) => item.id == categoryId)
        .firstOrNull;
    final children = store
        .visible('categories')
        .where((item) => item.text('parentId') == categoryId)
        .toList();
    final products = store
        .visible('products')
        .where((item) => item.text('categoryId') == categoryId)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(category?.text('name', 'Category') ?? 'Category'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (children.isNotEmpty) ...[
            pageHeadingText(
              context,
              layout: layoutFor(
                context,
                store.entries('settings'),
                'categoryPageHeading',
              ),
              defaultText: 'Subcategories',
              overridable: false,
            ),
            for (final child in children)
              ListTile(
                title: Text(child.text('name')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CategoryPage(store: store, categoryId: child.id),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 20),
          pageHeadingText(
            context,
            layout: layoutFor(
              context,
              store.entries('settings'),
              'categoryPageHeading',
            ),
            defaultText: '${products.length} products',
            overridable: false,
            translate: false,
          ),
          if (products.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('No products are available in this category yet.'),
            ),
          for (final product in products)
            ListTile(
              leading: SizedBox(
                width: 72,
                child: ProductArt(product, height: 64),
              ),
              title: Text(product.text('name')),
              subtitle: Text(money(product.price(store.pincode))),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ProductPage(store: store, entry: product),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
