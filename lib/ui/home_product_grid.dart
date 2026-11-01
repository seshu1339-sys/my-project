import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'layout_settings.dart';

class HomeProductGrid extends StatelessWidget {
  const HomeProductGrid({
    super.key,
    required this.entries,
    required this.itemBuilder,
    this.appearance = const Entry('', {}),
    this.smallestCard,
  });
  final List<Entry> entries;
  final Widget Function(Entry) itemBuilder;
  final Entry appearance;
  // How narrow a card may get; null = the usual size. The Android app passes less, so its Items in a row setting can fit 2 or 3 on a phone.
  final double? smallestCard;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final layout = ComponentLayout(
        appearance,
        MediaQuery.sizeOf(context).width,
      );
      final floor = smallestCard ?? (layout.padding * 2 + 150).clamp(180, 320).toDouble();
      final columns = layout.columns(
        c.maxWidth,
        preferred: 250,
        minimum: floor,
      );
      final slotWidth = (c.maxWidth - (columns - 1) * layout.gapX) / columns;
      final width = layout.width(
        slotWidth,
        fallback: slotWidth,
        floor: floor,
      );
      final rows = layout.rows;
      final visible = rows > 0 ? entries.take(rows * columns).toList() : entries;
      return Wrap(
        alignment: layout.alignment,
        spacing: layout.gapX,
        runSpacing: layout.gap,
        children: [
          for (final entry in visible)
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
