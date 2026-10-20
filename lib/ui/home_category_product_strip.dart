import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'shared.dart';

/// A horizontally-scrollable row of individual product cards (photo, name,
/// price) for one or more categories — matches the reference design's
/// "Fresh Fruits & Vegetables" strip, distinct from the full Featured
/// Products grid further down the page. The whole strip (heading text,
/// style, uniform card photo height/brightness) is one numbered "main"
/// element (see element_groups.dart's `crossSellStrip`); each card's own
/// color/image/brightness/text style is its own sub-number, never size.
class HomeCategoryProductStrip extends StatelessWidget {
  const HomeCategoryProductStrip({
    super.key,
    required this.layout,
    required this.defaultTitle,
    required this.icon,
    required this.products,
    required this.store,
    required this.onProduct,
    this.wrapProductItem = _identityItem,
  });
  final ComponentLayout layout;
  final String defaultTitle;
  final IconData icon;
  final List<Entry> products;
  final Store store;
  final ValueChanged<Entry> onProduct;
  final Widget Function(Entry product, Widget child) wrapProductItem;
  static Widget _identityItem(Entry product, Widget child) => child;

  @override
  Widget build(BuildContext context) {
    if (!layout.visible || products.isEmpty) return const SizedBox.shrink();
    final entry = layout.entry;
    final cardHeight = clampedNumber(entry, 'imageHeight', 70, 32, 400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: entry.text('textColor').isEmpty
                    ? AppTokens.primary
                    : colorFromHex(entry.text('textColor'), AppTokens.primary),
              ),
              const SizedBox(width: 8),
              Text(
                entry.text('text', defaultTitle).tr(context),
                style: sectionTextStyle(
                  entry,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
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
                    child: wrapProductItem(
                      product,
                      _ProductStripCard(
                        // Merges this one product's own override fields
                        // (set through its own numbered design panel) onto
                        // the shared template -- color/brightness/text
                        // style only; card photo height always comes from
                        // the main's own `imageHeight`, the same for every
                        // card, never from the product's own doc.
                        appearance: Entry(product.id, {
                          ...entry.data,
                          ...product.data,
                        }),
                        product: product,
                        price: product.price(store.pincode),
                        height: cardHeight,
                        onTap: () => onProduct(product),
                      ),
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
  const _ProductStripCard({
    required this.appearance,
    required this.product,
    required this.price,
    required this.height,
    required this.onTap,
  });
  final Entry appearance;
  final Entry product;
  final double price;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: colorFromHex(appearance.text('backgroundColor'), AppTokens.surface),
    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
    elevation: 0,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(
            color: appearance.text('borderColor').isEmpty
                ? AppTokens.border
                : colorFromHex(appearance.text('borderColor'), AppTokens.border),
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductArt(product, height: height, appearance: appearance),
            const SizedBox(height: 6),
            Text(
              product.text('name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sectionTextStyle(
                appearance,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${money(price)}/${product.text('unit').isEmpty ? 'unit' : product.text('unit')}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTokens.primary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
