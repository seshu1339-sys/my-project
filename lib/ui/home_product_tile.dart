import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'shared.dart';

class HomeProductTile extends StatelessWidget {
  const HomeProductTile({
    super.key,
    required this.entry,
    required this.price,
    required this.onOpen,
    required this.onAdd,
    this.preview = false,
    this.appearance,
    this.shopName = '',
  });
  final Entry entry;
  final double price;
  final VoidCallback? onOpen, onAdd;
  final bool preview;
  final Entry? appearance;
  // Resolved client-side from the already-loaded shops catalog (no new
  // Firestore read) by whoever builds this tile; purely cosmetic.
  final String shopName;
  @override
  Widget build(BuildContext context) {
    final layout = ComponentLayout(
      appearance ?? const Entry('', {}),
      MediaQuery.sizeOf(context).width,
    );
    final original = entry.number('compareAtPrice');
    final discount = original > price && price >= 0
        ? ((original - price) / original * 100).floor()
        : 0;
    return Material(
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: .18),
      color: colorFromHex(
        appearance?.text('backgroundColor') ?? '',
        AppTokens.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          clampedNumber(appearance ?? const Entry('', {}), 'radius', AppTokens.radiusLg, 0, 80),
        ),
        side: BorderSide(
          color: colorFromHex(
            appearance?.text('borderColor') ?? '',
            AppTokens.border,
          ),
          width: clampedNumber(
            appearance ?? const Entry('', {}),
            'borderWidth',
            1,
            0,
            8,
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.all(layout.padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ProductArt(
                    entry,
                    height:
                        layout.n(
                          'imageHeight',
                          MediaQuery.sizeOf(context).width >= 1100 ? 180 : 140,
                          32,
                          400,
                        ) *
                        layout.scale,
                    width: layout.n('imageWidth', 0, 0, 3840) > 0
                        ? layout.n('imageWidth', 0, 0, 3840) * layout.scale
                        : null,
                  ),
                  if (discount > 0 || preview)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTokens.accentRed,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          preview
                              ? 'PREVIEW'.tr(context)
                              : '{percent}% OFF'.tr(context, {'percent': '$discount'}),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                (entry.text('kind') == 'service'
                        ? 'LOCAL EXPERT'
                        : 'EVERYDAY PICK')
                    .tr(context),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppTokens.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.text('name'),
                style: sectionTextStyle(
                  appearance ?? const Entry('', {}),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ).copyWith(height: 1.3),
              ),
              if (shopName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storefront_outlined, size: 13, color: AppTokens.textMuted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        shopName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppTokens.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
              if (entry.number('avgRating') > 0) ...[
                const SizedBox(height: 4),
                RatingStars(
                  rating: entry.number('avgRating'),
                  count: entry.number('reviewCount').toInt(),
                  size: 13,
                ),
              ],
              const SizedBox(height: 12),
              if (discount > 0)
                Text(
                  money(original),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          money(price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          entry.data['unit'] == null
                              ? 'each'.tr(context)
                              : entry.text('unit'),
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Add {name} to bag'.tr(context, {'name': entry.text('name')}),
                    onPressed: onAdd,
                    style: IconButton.styleFrom(
                      backgroundColor: AppTokens.primary,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                    ),
                    icon: Icon(
                      Icons.add,
                      size: layout.n('iconSize', 21, 16, 40),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
