import 'package:flutter/material.dart';

import '../domain/catalog.dart';
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
                      child: Center(
                        child: entry.text('imageUrl').isEmpty
                            ? Icon(
                                icons[index % icons.length],
                                color: accent,
                                size: layout.n('iconSize', 30, 16, 72),
                              )
                            : ClipOval(
                                child: Image.network(
                                  entry.text('imageUrl'),
                                  width: badgeSize,
                                  height: badgeSize,
                                  fit: BoxFit.cover,
                                  color: imageBrightnessTint(appearance ?? const Entry('', {}))?.$1,
                                  colorBlendMode: imageBrightnessTint(appearance ?? const Entry('', {}))?.$2,
                                  errorBuilder: (_, e, s) => Icon(
                                    icons[index % icons.length],
                                    color: accent,
                                    size: layout.n('iconSize', 30, 16, 72),
                                  ),
                                ),
                              ),
                      ),
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
