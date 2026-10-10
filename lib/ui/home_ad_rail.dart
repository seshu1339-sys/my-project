import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'home_promotions.dart';
import 'layout_settings.dart';
import 'shared.dart';

/// Merges each ad/box promotion with its section's shared appearance config
/// (exactly as the desktop rail has always done), so the desktop rail and
/// the mobile/tablet carousel both render from one identical list — if an ad
/// shows on one, it shows on the other, with the same styling.
List<Entry> mergedPromoEntries({
  required List<Entry> ads,
  required Entry adAppearance,
  required List<Entry> boxes,
  required Entry boxAppearance,
}) => [
  for (final ad in ads) Entry(ad.id, {...adAppearance.data, ...ad.data}),
  for (final box in boxes) Entry(box.id, {...boxAppearance.data, ...box.data}),
];

/// The desktop right-side ad/box rail: ads and feature/promo boxes share one
/// vertical stack rather than boxes repeating as a separate full-width
/// section. On mobile/tablet this is replaced by `ScheduledPromoCarousel`
/// instead (see wireframe_home.dart) — both read from `mergedPromoEntries`
/// above so neither ever shows a different set of ads than the other.
class HomeAdRail extends StatelessWidget {
  const HomeAdRail({
    super.key,
    required this.adLayout,
    required this.boxLayout,
    required this.ads,
    required this.boxes,
    required this.onPromotion,
  });
  final ComponentLayout adLayout;
  final ComponentLayout boxLayout;
  final List<Entry> ads;
  final List<Entry> boxes;
  final ValueChanged<String> onPromotion;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      // Both ad boxes stacked and always visible (matches the reference
      // design's "Big Savings Everyday" + "Home Services At Your Doorstep"
      // shown together, not one rotating slot).
      if (adLayout.visible)
        LayoutSection(
          layout: adLayout,
          child: Column(
            children: [
              for (final ad in ads)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: ad.number('spacing', adLayout.gap).clamp(0, 64),
                  ),
                  child: ScheduledPromo(
                    entry: Entry(ad.id, {...adLayout.entry.data, ...ad.data}),
                    onTap: () => onPromotion(ad.text('target')),
                  ),
                ),
            ],
          ),
        ),
      if (boxes.isNotEmpty)
        LayoutSection(
          layout: boxLayout,
          child: Column(
            children: [
              for (final box in boxes)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: clampedNumber(box, 'spacing', boxLayout.gap, 0, 64),
                  ),
                  child: ScheduledPromo(
                    entry: Entry(box.id, {...boxLayout.entry.data, ...box.data}),
                    onTap: () => onPromotion(box.text('target')),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}
