import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'design_tokens.dart';
import 'shared.dart';

/// A horizontally-scrollable row of individual product cards (photo, name,
/// price) for one or more categories — matches the reference design's
/// "Fresh Fruits & Vegetables" strip, distinct from the full Featured
/// Products grid further down the page.
class HomeCategoryProductStrip extends StatelessWidget {
  const HomeCategoryProductStrip({
    super.key,
    required this.title,
    required this.icon,
    required this.products,
    required this.store,
    required this.onProduct,
  });
  final String title;
  final IconData icon;
  final List<Entry> products;
  final Store store;
  final ValueChanged<Entry> onProduct;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTokens.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final product in products) ...[
                  SizedBox(
                    width: 110,
                    child: _ProductStripCard(
                      product: product,
                      price: product.price(store.pincode),
                      onTap: () => onProduct(product),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductStripCard extends StatelessWidget {
  const _ProductStripCard({required this.product, required this.price, required this.onTap});
  final Entry product;
  final double price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppTokens.surface,
    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
    elevation: 0,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: AppTokens.border),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductArt(product, height: 70),
            const SizedBox(height: 6),
            Text(
              product.text('name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(
              '${money(price)}/${product.text('unit').isEmpty ? 'unit' : product.text('unit')}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTokens.primary),
            ),
          ],
        ),
      ),
    ),
  );
}
