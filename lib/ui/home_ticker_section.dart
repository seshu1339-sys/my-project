import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'shared.dart';

/// The "Today's Best Offers" strip at the top of the homepage: a label
/// (admin-overridable, defaults to "Today's Best Offers in `<location>`") plus
/// a horizontally scrollable row of real product/price chips — matches the
/// reference design's price-chip ticker rather than a scrolling marquee.
/// Chips prefer genuinely discounted products (`compareAtPrice` > `price`); if
/// none are discounted, the first few catalog products fill the row instead.
class HomeTickerSection extends StatelessWidget {
  const HomeTickerSection({
    super.key,
    required this.store,
    required this.settings,
    required this.promotions,
    required this.products,
    required this.onProduct,
  });
  final Store store;
  final List<Entry> settings;
  final List<Entry> promotions;
  final List<Entry> products;
  final ValueChanged<Entry> onProduct;

  @override
  Widget build(BuildContext context) {
    final tickerSettings = store
        .visible('settings')
        .where((e) => e.id == 'scrollingText')
        .firstOrNull;
    final noticeLayout = layoutFor(context, settings, 'notice');
    final ticker = Entry('notice', {
      ...?tickerSettings?.data,
      ...noticeLayout.entry.data,
    });
    final translations = ticker.data['translations'];
    final location = store.address.isNotEmpty
        ? store.address
        : store.pincode.isNotEmpty
        ? store.pincode
        : 'your area'.tr(context);
    final label = translations is Map && translations[store.language] != null
        ? translations[store.language].toString()
        : ticker.text('text').isNotEmpty
        ? ticker.text('text')
        : 'Today\'s Best Offers in {location}'.tr(context, {
            'location': location,
          });
    final discounted = products
        .where((p) => p.number('compareAtPrice', 0) > p.number('price', 0))
        .toList();
    final chips = (discounted.isNotEmpty ? discounted : products)
        .take(8)
        .toList();
    if (chips.isEmpty || !noticeLayout.visible) return const SizedBox.shrink();
    return LayoutSection(
      layout: noticeLayout,
      child: Container(
        width: double.infinity,
        // entryDecoration (not a hand-rolled BoxDecoration) so this strip
        // can be a real photo banner -- background image, brightness,
        // gradient, border -- same mechanism every other decorated
        // section already uses, not something new just for this one. At
        // its defaults (no backgroundImage/gradient/border ever set) this
        // produces the exact same look as before.
        decoration: entryDecoration(
          ticker,
          fallback: const Color(0xffe8f3fb),
          defaultRadius: 8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // The whole strip (label + chips) scrolls together as one row rather
        // than splitting into Flexible/Expanded regions — at very narrow
        // widths (phone, or squeezed beside the "All Categories" button)
        // that split could demand more space than was available and
        // overflow; a single scrollable row can never overflow by
        // construction, it just scrolls further.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Icon(
                Icons.campaign,
                size: 18,
                color: colorFromHex(
                  ticker.text('textColor'),
                  AppTokens.primaryDark,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                maxLines: 1,
                style:
                    sectionTextStyle(
                      ticker,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ).copyWith(
                      color: ticker.text('textColor').isEmpty
                          ? AppTokens.primaryDark
                          : colorFromHex(
                              ticker.text('textColor'),
                              AppTokens.primaryDark,
                            ),
                    ),
              ),
              const SizedBox(width: 12),
              for (final product in chips) ...[
                _OfferChip(product: product, onTap: () => onProduct(product)),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferChip extends StatelessWidget {
  const _OfferChip({required this.product, required this.onTap});
  final Entry product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: product.text('imageUrl').isEmpty
                  ? Icon(
                      Icons.local_offer_outlined,
                      size: 16,
                      color: AppTokens.primary,
                    )
                  : Image.network(
                      product.text('imageUrl'),
                      width: 20,
                      height: 20,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, s) => Icon(
                        Icons.local_offer_outlined,
                        size: 16,
                        color: AppTokens.primary,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Text(
              product.text('name'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Text(
              '${money(product.number('price', 0))}/${product.text('unit').isEmpty ? 'unit' : product.text('unit')}',
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
