import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'shared.dart';

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
    child: Row(
      children: [
        Expanded(
          child: Column(
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
          ),
        ),
        if (action != null)
          TextButton(onPressed: action, child: Text(actionLabel)),
      ],
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
    return SizedBox(
      width: 112,
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
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Column(
                children: [
                  if (entry.text('imageUrl').isNotEmpty)
                    ProductArt(entry, height: 44)
                  else
                    Icon(
                      icons[index % icons.length],
                      color: const Color(0xff176b50),
                      size: 30,
                    ),
                  const SizedBox(height: 10),
                  Text(
                    entry.text('name'),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: sectionTextStyle(
                      appearance ?? const Entry('', {}),
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
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
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ProductArt(entry, height: 140),
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
                          preview ? 'PREVIEW' : '$discount% OFF',
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
                entry.text('kind') == 'service'
                    ? 'LOCAL EXPERT'
                    : 'EVERYDAY PICK',
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sectionTextStyle(
                  appearance ?? const Entry('', {}),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ).copyWith(height: 1.3),
              ),
              const Spacer(),
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
                          entry.text('unit', 'each'),
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
                    tooltip: 'Add ${entry.text('name')} to bag',
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 21),
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
  });
  final List<Entry> entries;
  final Widget Function(Entry) itemBuilder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = c.maxWidth >= 840
          ? 4
          : c.maxWidth >= 610
          ? 3
          : c.maxWidth >= 310
          ? 2
          : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: entries.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 345 + (scale - 1).clamp(0, 3) * 160,
        ),
        itemBuilder: (_, i) => itemBuilder(entries[i]),
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
                    ? 'Sample shop • coming soon'
                    : entry.text('address', 'Explore this local shop'),
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
                      preview ? 'Preview' : 'Explore shop',
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
