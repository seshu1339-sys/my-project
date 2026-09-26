import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/strings.dart';
import 'shared.dart';
import 'layout_settings.dart';

class HomeSectionHeading extends StatelessWidget {
  const HomeSectionHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.actionLabel = 'View all',
    this.appearance,
  });
  final String title, subtitle, actionLabel;
  final VoidCallback? action;
  final Entry? appearance;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 16),
    child: LayoutBuilder(
      builder: (context, c) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: sectionTextStyle(
                appearance ?? const Entry('', {}),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        );
        final button = action == null
            ? null
            : TextButton(onPressed: action, child: Text(actionLabel));
        if (c.maxWidth < 600 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, ?button],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            ?button,
          ],
        );
      },
    ),
  );
}

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
    return SizedBox(
      width: 160,
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected
              ? colorFromHex(
                  appearance?.text('selectedColor') ?? '',
                  const Color(0xffe3eddc),
                )
              : colorFromHex(
                  appearance?.text('backgroundColor') ?? '',
                  Colors.white,
                ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(layout.radius),
            side: BorderSide(
              color: colorFromHex(
                layout.entry.text('borderColor'),
                const Color(0xffe6eae3),
              ),
              width: layout.n('borderWidth', 0, 0, 8),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(layout.radius),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(layout.padding),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (entry.text('imageUrl').isNotEmpty)
                        ProductArt(
                          entry,
                          height: layout.n('imageHeight', 56, 32, 120),
                        )
                      else
                        Icon(
                          icons[index % icons.length],
                          color: const Color(0xff176b50),
                          size: layout.n('iconSize', 40, 16, 72),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        entry.text('name'),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: sectionTextStyle(
                          appearance ?? const Entry('', {}),
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeProductTile extends StatelessWidget {
  const HomeProductTile({
    super.key,
    required this.entry,
    required this.price,
    required this.onOpen,
    required this.onAdd,
    this.preview = false,
    this.appearance,
  });
  final Entry entry;
  final double price;
  final VoidCallback? onOpen, onAdd;
  final bool preview;
  final Entry? appearance;
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
      color: colorFromHex(
        appearance?.text('backgroundColor') ?? '',
        Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          clampedNumber(appearance ?? const Entry('', {}), 'radius', 20, 0, 80),
        ),
        side: BorderSide(
          color: colorFromHex(
            appearance?.text('borderColor') ?? '',
            const Color(0xffe6eae3),
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
                          color: const Color(0xff176b50),
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
                  color: Color(0xff176b50),
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
              const SizedBox(height: 16),
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

class HomeProductGrid extends StatelessWidget {
  const HomeProductGrid({
    super.key,
    required this.entries,
    required this.itemBuilder,
    this.appearance = const Entry('', {}),
  });
  final List<Entry> entries;
  final Widget Function(Entry) itemBuilder;
  final Entry appearance;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final layout = ComponentLayout(
        appearance,
        MediaQuery.sizeOf(context).width,
      );
      final columns = layout.columns(
        c.maxWidth,
        preferred: 250,
        minimum: (layout.padding * 2 + 150).clamp(180, 320),
      );
      final slotWidth = (c.maxWidth - (columns - 1) * layout.gap) / columns;
      final width = layout.width(
        slotWidth,
        fallback: slotWidth,
        floor: (layout.padding * 2 + 150).clamp(180, 320),
      );
      return Wrap(
        spacing: layout.gap,
        runSpacing: layout.gap,
        children: [
          for (final entry in entries)
            SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: layout.height(0)),
                child: itemBuilder(entry),
              ),
            ),
        ],
      );
    },
  );
}

class HomeShopTile extends StatelessWidget {
  const HomeShopTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.preview = false,
  });
  final Entry entry;
  final VoidCallback? onTap;
  final bool preview;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 270,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductArt(entry, height: 94),
              const SizedBox(height: 12),
              Text(
                entry.text('name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                preview
                    ? 'Sample shop • coming soon'.tr(context)
                    : (entry.data['address'] == null
                          ? 'Explore this local shop'.tr(context)
                          : entry.text('address')),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    size: 16,
                    color: Color(0xff176b50),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (preview ? 'Preview' : 'Explore shop').tr(context),
                      style: const TextStyle(
                        color: Color(0xff176b50),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
