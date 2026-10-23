import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'home_category_tile.dart';
import 'home_section_heading.dart';
import 'layout_settings.dart';
import 'shared.dart';

/// The Categories homepage section: heading + a responsive icon-tile grid
/// whose column count/tile size come from the admin-configured layout.
class HomeCategoriesSection extends StatelessWidget {
  const HomeCategoriesSection({
    super.key,
    required this.categoryLayout,
    required this.categories,
    required this.categoriesKey,
    required this.onCategory,
    required this.moreTileLayout,
    this.wrapSection = _identitySection,
    this.wrapCategoryItem = _identityItem,
  });
  final ComponentLayout categoryLayout;
  final List<Entry> categories;
  final GlobalKey categoriesKey;
  final ValueChanged<String> onCategory;
  final ComponentLayout moreTileLayout;
  final Widget Function(String sectionKey, Widget child) wrapSection;
  static Widget _identitySection(String sectionKey, Widget child) => child;
  // Admin Visual Editor hook: wraps one individual category tile (not the
  // whole row) in click-to-select, keyed by that category's own Firestore
  // id -- same shape as HomeAdRail's wrapItem for ads/boxes. Null on the
  // real customer site.
  final Widget Function(Entry category, Widget child) wrapCategoryItem;
  static Widget _identityItem(Entry category, Widget child) => child;

  @override
  Widget build(BuildContext context) => LayoutSection(
    layout: ComponentLayout(
      Entry(categoryLayout.entry.id, {
        'visible': categoryLayout.visible,
        'margin': categoryLayout.margin,
      }),
      categoryLayout.viewport,
    ),
    child: LayoutBuilder(
      builder: (context, c) {
        final tileWidth = categoryLayout.width(
          c.maxWidth,
          fallback: 125,
          floor: 80,
        );
        return Column(
          key: categoriesKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeSectionHeading(
              title: categoryLayout.entry
                  .text('text', 'Categories')
                  .tr(context),
              subtitle: 'Browse your everyday essentials'.tr(context),
              appearance: categoryLayout.entry,
            ),
            if (categories.isEmpty)
              Text('Categories will appear here when available.'.tr(context)),
            // A single horizontally scrolling row (swipeable) rather than a
            // wrapping grid, so every category stays reachable on any screen
            // width without the row ever growing taller than one tile.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (i, category) in categories.indexed)
                    Padding(
                      padding: EdgeInsets.only(
                        right: i == categories.length - 1
                            ? 0
                            : categoryLayout.gap,
                      ),
                      child: SizedBox(
                        width: tileWidth,
                        height: categoryLayout.height(125, floor: 125),
                        // Merges this one category's own override fields
                        // (set through its own numbered design panel) onto
                        // the shared template -- color/brightness/text
                        // style only; size always comes from tileWidth/
                        // height above, the same for every tile, never
                        // from the category's own doc.
                        child: wrapCategoryItem(
                          category,
                          HomeCategoryTile(
                            entry: category,
                            selected: false,
                            onTap: () => onCategory(category.id),
                            index: i,
                            appearance: Entry(category.id, {
                              ...categoryLayout.styled(context).data,
                              ...category.data,
                            }),
                          ),
                        ),
                      ),
                    ),
                  if (moreTileLayout.visible)
                    SizedBox(
                      width: tileWidth,
                      height: categoryLayout.height(125, floor: 125),
                      child: wrapSection(
                        'moreCategoriesTile',
                        _MoreCategoriesTile(
                          onTap: () => onCategory(''),
                          layout: moreTileLayout,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _MoreCategoriesTile extends StatelessWidget {
  const _MoreCategoriesTile({required this.onTap, required this.layout});
  final VoidCallback onTap;
  final ComponentLayout layout;

  @override
  Widget build(BuildContext context) {
    final entry = layout.entry;
    final badgeSize = entry.number('iconSize') > 0
        ? clampedNumber(entry, 'iconSize', 56, 16, 120)
        : 56.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: badgeSize,
                    height: badgeSize,
                    decoration: BoxDecoration(
                      color: entry.text('backgroundColor').isEmpty
                          ? AppTokens.tintFor(0)
                          : colorFromHex(
                              entry.text('backgroundColor'),
                              AppTokens.tintFor(0),
                            ),
                      shape: BoxShape.circle,
                    ),
                    child: entry.text('iconUrl').isEmpty
                        ? const Icon(Icons.grid_view_rounded)
                        : ClipOval(
                            child: Image.network(
                              entry.text('iconUrl'),
                              width: badgeSize,
                              height: badgeSize,
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stack) =>
                                  const Icon(Icons.grid_view_rounded),
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    entry.text('text', 'More Categories').tr(context),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sectionTextStyle(
                      entry,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
