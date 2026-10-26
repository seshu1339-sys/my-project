import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/fresh_strip.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'shared.dart';

/// The "Fresh Fruits & Vegetables" strip of product cards (photo, name,
/// price), distinct from the full Featured Products grid further down the
/// page: 9 cards at a time, fitted to the width (9, 5 or 3 a row), then the
/// next 9 after a while, round and round (lib/domain/fresh_strip.dart). The
/// whole strip (heading text, style, card photo brightness) is one numbered
/// "main" element (see element_groups.dart's `crossSellStrip`); each card's
/// own color/image/brightness/text style is its own sub-number, never size.
class HomeCategoryProductStrip extends StatefulWidget {
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
  State<HomeCategoryProductStrip> createState() => _HomeCategoryProductStripState();
}

class _HomeCategoryProductStripState extends State<HomeCategoryProductStrip> {
  Timer? timer;
  int page = 0;

  @override
  void initState() {
    super.initState();
    // The admin's timing for the strip (Layout), else 5 seconds a group.
    final ms = widget.layout.entry.number('animationMs', 5000).clamp(2000, 60000).round();
    timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (mounted && widget.products.length > freshStripPageSize) setState(() => page++);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout, products = widget.products, store = widget.store, icon = widget.icon;
    if (!layout.visible || products.isEmpty) return const SizedBox.shrink();
    final entry = layout.entry;
    final pages = pagesOf(products);
    final shown = pages[page % pages.length];
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
              // Flexible: a long title in a narrow column is cut with "..." instead of overflowing the row.
              Flexible(
                child: Text(
                  entry.text('text', widget.defaultTitle).tr(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sectionTextStyle(
                    entry,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              const gap = 10.0;
              // 9 a row when they fit at 100 px each, else 5 (two rows), else 3 (three rows, a phone).
              final columns = c.maxWidth >= 9 * 100 + 8 * gap ? 9 : c.maxWidth >= 5 * 100 + 4 * gap ? 5 : 3;
              final cardWidth = (c.maxWidth - (columns - 1) * gap) / columns;
              // The same photo size on every card: the admin's photo height, but never small beside the card's width.
              final photo = max(clampedNumber(entry, 'imageHeight', 70, 32, 400), cardWidth * .62);
              final rows = [for (var i = 0; i < shown.length; i += columns) shown.sublist(i, min(i + columns, shown.length))];
              return AnimatedSwitcher(
                duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 500),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: Tween(begin: const Offset(.08, 0), end: Offset.zero).animate(animation), child: child),
                ),
                child: Column(
                  key: ValueKey('fresh-page-${page % pages.length}'),
                  children: [
                    for (final (r, row) in rows.indexed) ...[
                      if (r > 0) const SizedBox(height: gap),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < columns; i++) ...[
                            if (i > 0) const SizedBox(width: gap),
                            Expanded(
                              child: i >= row.length
                                  ? const SizedBox.shrink()
                                  : widget.wrapProductItem(
                                      row[i],
                                      _ProductStripCard(
                                        // Merges this one product's own override fields
                                        // (set through its own numbered design panel) onto
                                        // the shared template -- color/brightness/text
                                        // style only; card photo height is the same for every
                                        // card, never from the product's own doc.
                                        appearance: Entry(row[i].id, {
                                          ...entry.data,
                                          ...row[i].data,
                                        }),
                                        product: row[i],
                                        price: row[i].price(store.pincode),
                                        height: photo,
                                        onTap: () => widget.onProduct(row[i]),
                                      ),
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          if (pages.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i == page % pages.length ? AppTokens.primary : AppTokens.border),
                    ),
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
