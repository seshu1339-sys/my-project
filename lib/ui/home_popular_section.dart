import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/strings.dart';
import 'home_widgets.dart';
import 'layout_settings.dart';
import 'home_section_config.dart';
import 'shared.dart';

/// The "Popular Products" / "Featured Products" homepage section (also
/// doubles as search results when the customer has typed into the header
/// search box). Shows an "All" + per-category filter tab row above the grid
/// — stateful locally since the selection only affects this section's own
/// display, independent of the header search.
class HomePopularSection extends StatefulWidget {
  const HomePopularSection({
    super.key,
    required this.store,
    required this.settings,
    required this.productLayout,
    required this.products,
    required this.categories,
    required this.productsKey,
    required this.searchText,
    required this.shopNameById,
    required this.onProduct,
    required this.onAdd,
    this.wrapSection = _identitySection,
  });
  final Store store;
  final List<Entry> settings;
  final ComponentLayout productLayout;
  final List<Entry> products;
  final List<Entry> categories;
  final GlobalKey productsKey;
  final String searchText;
  final Map<String, String> shopNameById;
  final ValueChanged<Entry> onProduct, onAdd;
  final Widget Function(String sectionKey, Widget child) wrapSection;
  static Widget _identitySection(String sectionKey, Widget child) => child;

  @override
  State<HomePopularSection> createState() => _HomePopularSectionState();
}

class _HomePopularSectionState extends State<HomePopularSection> {
  String filter = '';

  @override
  Widget build(BuildContext context) {
    final tabCategories = widget.categories
        .where((c) => widget.products.any((p) => p.text('categoryId') == c.id))
        .toList();
    final filtered = filter.isEmpty
        ? widget.products
        : widget.products.where((p) => p.text('categoryId') == filter).toList();
    return LayoutSection(
      layout: layoutFor(context, widget.settings, 'popular'),
      child: Column(
        key: widget.productsKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeSectionHeading(
            title: widget.searchText.isEmpty
                ? sectionConfig(widget.settings, 'popular').text('text', 'Popular Products').tr(context)
                : 'Search results'.tr(context),
            subtitle: widget.searchText.isEmpty
                ? 'Products and services from your neighbourhood'.tr(context)
                : '{count} matching items'.tr(context, {'count': '${widget.products.length}'}),
            appearance: sectionConfig(widget.settings, 'popular'),
          ),
          if (widget.searchText.isEmpty && tabCategories.isNotEmpty)
            widget.wrapSection(
              'popularFilterChips',
              Builder(
                builder: (context) {
                  final chips = layoutFor(context, widget.settings, 'popularFilterChips');
                  if (!chips.visible) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text('All'.tr(context)),
                            selected: filter.isEmpty,
                            selectedColor: chips.entry.text('backgroundColor').isEmpty
                                ? null
                                : colorFromHex(chips.entry.text('backgroundColor'), Colors.transparent),
                            labelStyle: chips.entry.text('textColor').isEmpty
                                ? null
                                : TextStyle(color: colorFromHex(chips.entry.text('textColor'), Colors.black87)),
                            onSelected: (_) => setState(() => filter = ''),
                          ),
                          for (final category in tabCategories) ...[
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(category.text('name')),
                              selected: filter == category.id,
                              selectedColor: chips.entry.text('backgroundColor').isEmpty
                                  ? null
                                  : colorFromHex(chips.entry.text('backgroundColor'), Colors.transparent),
                              labelStyle: chips.entry.text('textColor').isEmpty
                                  ? null
                                  : TextStyle(color: colorFromHex(chips.entry.text('textColor'), Colors.black87)),
                              onSelected: (_) => setState(() => filter = category.id),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No matching products. Try another search.'.tr(context),
              ),
            ),
          if (widget.productLayout.visible)
            HomeProductGrid(
              entries: filtered,
              appearance: widget.productLayout.entry,
              itemBuilder: (entry) => HomeProductTile(
                entry: entry,
                price: entry.price(widget.store.pincode),
                appearance: widget.productLayout.styled(context, fontSize: 16),
                shopName: widget.shopNameById[entry.text('shopId')] ?? '',
                onOpen: () => widget.onProduct(entry),
                onAdd: entry.number('stock') > (widget.store.cart[entry.id] ?? 0)
                    ? () => widget.onAdd(entry)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
