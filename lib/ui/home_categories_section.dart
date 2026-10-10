import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'home_widgets.dart';
import 'layout_settings.dart';

/// The Categories homepage section: heading + a responsive icon-tile grid
/// whose column count/tile size come from the admin-configured layout.
class HomeCategoriesSection extends StatelessWidget {
  const HomeCategoriesSection({
    super.key,
    required this.categoryLayout,
    required this.categories,
    required this.categoriesKey,
    required this.onCategory,
  });
  final ComponentLayout categoryLayout;
  final List<Entry> categories;
  final GlobalKey categoriesKey;
  final ValueChanged<String> onCategory;

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
        final tileWidth = categoryLayout.width(c.maxWidth, fallback: 125, floor: 80);
        return Column(
          key: categoriesKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeSectionHeading(
              title: 'Categories'.tr(context),
              subtitle: 'Browse your everyday essentials'.tr(context),
              appearance: categoryLayout.entry,
            ),
            if (categories.isEmpty)
              Text(
                'Categories will appear here when available.'.tr(context),
              ),
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
                        right: i == categories.length - 1 ? 0 : categoryLayout.gap,
                      ),
                      child: SizedBox(
                        width: tileWidth,
                        height: categoryLayout.height(125, floor: 125),
                        child: HomeCategoryTile(
                          entry: category,
                          selected: false,
                          onTap: () => onCategory(category.id),
                          index: i,
                          appearance: categoryLayout.styled(context),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: tileWidth,
                    height: categoryLayout.height(125, floor: 125),
                    child: _MoreCategoriesTile(onTap: () => onCategory('')),
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
  const _MoreCategoriesTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
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
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTokens.tintFor(0),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.grid_view_rounded),
                ),
                const SizedBox(height: 10),
                Text(
                  'More Categories'.tr(context),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
