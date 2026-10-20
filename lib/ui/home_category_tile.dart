import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../domain/category_images.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'shared.dart';

class HomeCategoryTile extends StatelessWidget {
  const HomeCategoryTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.index,
    this.appearance,
  });
  final Entry entry;
  final bool selected;
  final VoidCallback onTap;
  final int index;
  final Entry? appearance;
  /// The category's photo filling the circle: the admin's own photo (image
  /// URL) if set, else the built-in one for that category, else its icon.
  /// Every circle is the same [badgeSize]; the photo is cropped to fill it.
  Widget _photo(
    double badgeSize,
    ComponentLayout layout,
    Color accent,
    List<IconData> icons,
  ) {
    final fallback = Icon(
      icons[index % icons.length],
      color: accent,
      size: layout.n('iconSize', 30, 16, 72),
    );
    final url = entry.text('imageUrl');
    final builtIn = url.isEmpty ? builtInCategoryImage(entry) : null;
    if (url.isEmpty && builtIn == null) return fallback;
    final tint = imageBrightnessTint(appearance ?? const Entry('', {}));
    Widget broken(BuildContext _, Object e, StackTrace? s) => fallback;
    return ClipOval(
      child: builtIn != null
          ? Image.asset(
              builtIn,
              key: ValueKey('category-photo-${entry.id}'),
              width: badgeSize,
              height: badgeSize,
              fit: BoxFit.cover,
              color: tint?.$1,
              colorBlendMode: tint?.$2,
              errorBuilder: broken,
            )
          : Image.network(
              url,
              key: ValueKey('category-photo-${entry.id}'),
              width: badgeSize,
              height: badgeSize,
              fit: BoxFit.cover,
              color: tint?.$1,
              colorBlendMode: tint?.$2,
              errorBuilder: broken,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.grid_view_rounded,
      Icons.eco_outlined,
      Icons.chair_outlined,
      Icons.headphones_outlined,
      Icons.home_repair_service_outlined,
      Icons.kitchen_outlined,
    ];
    final layout = ComponentLayout(
      appearance ?? const Entry('', {}),
      MediaQuery.sizeOf(context).width,
    );
    final accent = AppTokens.accentFor(index);
    final badgeSize = layout.n('imageHeight', 68, 40, 120);
    final badgeColor = selected
        ? colorFromHex(appearance?.text('selectedColor') ?? '', accent.withValues(alpha: .22))
        : colorFromHex(appearance?.text('backgroundColor') ?? '', AppTokens.tintFor(index));
    return Semantics(
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(layout.padding.clamp(6, 16)),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: badgeSize,
                      height: badgeSize,
                      decoration: BoxDecoration(
                        color: badgeColor,
                        shape: BoxShape.circle,
                        border: selected ? Border.all(color: accent, width: 2) : null,
                        boxShadow: AppTokens.shadowSoft,
                      ),
                      child: Center(child: _photo(badgeSize, layout, accent, icons)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      entry.text('name'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sectionTextStyle(
                        appearance ?? const Entry('', {}),
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
