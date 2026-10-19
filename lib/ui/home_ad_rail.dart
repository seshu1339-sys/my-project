import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'home_promotions.dart';
import 'layout_settings.dart';
import 'shared.dart';

/// The wireframe's "ADS" rail specifically wants a red border on every ad
/// box by default. Per-ad or per-section (adLayout) `borderColor` still
/// overrides this exactly as before — this only fills in when neither has
/// set one.
Entry _withAdBorderDefault(Entry entry) => entry.text('borderColor').isEmpty
    ? Entry(entry.id, {...entry.data, 'borderColor': '#D32F2F', 'borderWidth': 2.0})
    : entry;

/// The wireframe draws every ADS box the exact same size. The per-ad
/// `width` override (used to let each ad be individually resized in the
/// Visual Editor) is dropped here so every ad falls back to the one shared
/// width from `adLayout` -- every other per-ad field (name, description,
/// image, target, colors, ...) still applies as-is. Height is handled
/// separately (see `heightOverride` on `ScheduledPromo`), not through this
/// data merge, since `ComponentLayout.height()` and `PromoCard`'s own
/// minimum-height fallback don't agree on whether the field is pre- or
/// post-scale -- passing one pre-computed pixel value straight through
/// both layers avoids relying on them agreeing.
Entry _withUniformAdWidth(Entry merged, ComponentLayout adLayout) {
  final data = {...merged.data};
  if (adLayout.entry.data.containsKey('width')) {
    data['width'] = adLayout.entry.data['width'];
  } else {
    data.remove('width');
  }
  return Entry(merged.id, data);
}

/// Commits one dimension (`width`/`height`) onto a single ad/box promotion
/// doc, preserving every other field — the exact same read-merge-save
/// pattern as `adjustSectionField` in `home_section_config.dart`, just
/// targeting one `promotions` entry instead of a shared `settings/section_*`
/// doc. This is what lets each ad/box be resized independently in the
/// Visual Editor: dragging one never touches the shared `ads`/`boxes`
/// appearance defaults, only this one entry's own `width`/`height`.
Future<void> adjustPromoDimension(Store store, String id, String field, double value) async {
  final current = store.entries('promotions').firstWhere(
    (e) => e.id == id,
    orElse: () => Entry(id, const {}),
  );
  await store.save('promotions', Entry(id, {...current.data, field: value}));
}

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
    required this.adsLabelLayout,
    this.wrapItem,
    this.wrapSection = _identitySection,
  });
  final ComponentLayout adLayout;
  final ComponentLayout boxLayout;
  final List<Entry> ads;
  final List<Entry> boxes;
  final ValueChanged<String> onPromotion;
  final ComponentLayout adsLabelLayout;
  // Admin Visual Editor hook: when provided, wraps each INDIVIDUAL ad/box
  // (not the rail as a whole) so each one gets its own selection border,
  // ghost outline and 8 resize handles, independent of its neighbors. Null
  // on the real customer site — this widget's own rendering is otherwise
  // completely unchanged either way.
  final Widget Function(Entry entry, String kind, Widget child)? wrapItem;
  // Same hook as HomeAdRail's sibling sections -- just for the fixed "ADS"
  // label, not the per-ad items above (those use wrapItem instead).
  final Widget Function(String sectionKey, Widget child) wrapSection;
  static Widget _identitySection(String sectionKey, Widget child) => child;

  Widget _item(Entry entry, String kind, Widget child) =>
      wrapItem == null ? child : wrapItem!(entry, kind, child);

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ads.isNotEmpty && adsLabelLayout.visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: wrapSection(
                    'adsLabel',
                    Text(
                      adsLabelLayout.entry.text('text', 'ADS').tr(context),
                      style: sectionTextStyle(
                        adsLabelLayout.entry,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ).copyWith(
                        letterSpacing: 1.2,
                        color: adsLabelLayout.entry.text('textColor').isEmpty
                            ? AppTokens.textMuted
                            : colorFromHex(adsLabelLayout.entry.text('textColor'), AppTokens.textMuted),
                      ),
                    ),
                  ),
                ),
              for (final ad in ads)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: ad.number('spacing', adLayout.gap).clamp(0, 64),
                  ),
                  child: _item(
                    ad,
                    'ad',
                    ScheduledPromo(
                      // One shared height computed ONCE from adLayout (not
                      // per-ad) and passed straight through, so every ad box
                      // is visually identical regardless of how much its
                      // own title/description text wraps.
                      heightOverride: adLayout.height(240, floor: 120),
                      entry: _withAdBorderDefault(
                        _withUniformAdWidth(Entry(ad.id, {...adLayout.entry.data, ...ad.data}), adLayout),
                      ),
                      onTap: () => onPromotion(ad.text('target')),
                    ),
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
                  child: _item(
                    box,
                    'box',
                    ScheduledPromo(
                      entry: Entry(box.id, {...boxLayout.entry.data, ...box.data}),
                      onTap: () => onPromotion(box.text('target')),
                    ),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}
