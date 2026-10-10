import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'design_tokens.dart';

Color colorFromHex(String value, Color fallback) {
  final normalized = value.trim().replaceFirst('#', '');
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null || (normalized.length != 6 && normalized.length != 8)) {
    return fallback;
  }
  return Color(normalized.length == 6 ? 0xff000000 | parsed : parsed);
}

double clampedNumber(
  Entry entry,
  String key,
  double fallback,
  double min,
  double max,
) {
  final value = entry.number(key, fallback);
  return (value.isFinite ? value : fallback).clamp(min, max).toDouble();
}

Entry sectionConfig(List<Entry> settings, String section) =>
    settings.firstWhere(
      (entry) => entry.id == 'section_$section',
      orElse: () => const Entry('', {}),
    );

// The content section an admin picks (e.g. 'products', a Firestore
// collection) is a different key from the layout component that actually
// controls that section's on-page size (e.g. 'popular', what WireframeHome
// reads via layoutFor) — resize/reorder always act on the layout key. Shared
// by admin.dart's Page-view dashboard and the Visual Editor's on-preview
// resize handle so both write the identical field, not two implementations.
Future<void> adjustSectionField(Store store, String layoutKey, String field, Object value) async {
  final saved = sectionConfig(store.entries('settings'), layoutKey);
  await store.save(
    'settings',
    Entry('section_$layoutKey', {...saved.data, field: value}),
  );
}

Future<void> adjustSectionHeight(Store store, String layoutKey, double height) =>
    adjustSectionField(store, layoutKey, 'height', height);

/// Moves a `reorderableHomeSections` entry from `oldIndex` to `newIndex`
/// (after the move, not before — same convention as Flutter's own
/// `ReorderableListView.onReorder`) and re-stamps every section's `order`
/// field from its new position. Shared by admin.dart's Page-view
/// `ReorderableListView` and the Visual Editor's drag handle so both move
/// sections through the identical write, not two implementations.
Future<void> reorderHomeSections(Store store, int oldIndex, int newIndex) async {
  final settings = store.entries('settings');
  final keys = [...reorderableHomeSections]
    ..sort((a, b) => sectionOrder(settings, a.key).compareTo(sectionOrder(settings, b.key)));
  final moved = keys.removeAt(oldIndex);
  keys.insert(newIndex, moved);
  for (final (index, descriptor) in keys.indexed) {
    final saved = sectionConfig(settings, descriptor.key);
    await store.save(
      'settings',
      Entry('section_${descriptor.key}', {...saved.data, 'order': (index + 1) * 10.0}),
    );
  }
}

bool sectionVisible(Entry config) =>
    config.id.isEmpty ||
    (config.data['visible'] != 'false' && config.data['visible'] != false);

/// One admin-reorderable home page section: its layout key (what
/// `WireframeHome`/`sectionOrder`/`sectionConfig` actually read — a
/// layout-component key, the same ones `layoutComponents`/`layoutFor` in
/// layout_settings.dart use, NOT a content-collection name), the generic
/// collection that tapping it in the admin "Page view" preview should open
/// (`targetSection`), and that preview's static title/icon. Bundling these
/// together — instead of keeping a bare key list in this file and a
/// separately-maintained title/icon map in admin.dart — makes it impossible
/// to add a section here and forget its admin-preview entry: that used to be
/// two independently-maintained lists that had to be kept in sync by hand,
/// and forgetting the second one crashed the admin preview at runtime
/// (a force-unwrapped lookup miss), caught only by a test, not the compiler.
class SectionDescriptor {
  const SectionDescriptor(this.key, this.targetSection, this.title, this.icon);
  final String key;
  final String targetSection;
  final String title;
  final IconData icon;
}

/// 'localServices' is distinct from the unrelated 'services' key (the
/// header's nav button) — reusing that key would corrupt the button's own
/// layout doc. 'notice' (the ticker) is deliberately NOT in this list — it
/// now has a fixed position beside the "All Categories" button rather than
/// being reorderable among the other sections (see wireframe_home.dart).
/// Its own show/hide still works via Section Customization as before.
const reorderableHomeSections = [
  SectionDescriptor('promo', 'promotions', 'Promotions (banner carousel)', Icons.local_offer_outlined),
  SectionDescriptor('categories', 'categories', 'Categories', Icons.grid_view_outlined),
  SectionDescriptor('popular', 'products', 'Products & services', Icons.shopping_bag_outlined),
  SectionDescriptor('localServices', 'products', 'Local Services', Icons.home_repair_service_outlined),
];

const _defaultSectionOrder = {
  'notice': 10.0,
  'promo': 20.0,
  'categories': 30.0,
  'popular': 40.0,
  'localServices': 45.0,
};

double sectionOrder(List<Entry> settings, String section) {
  final stored = sectionConfig(settings, section).number('order', -1);
  return stored >= 0 ? stored : (_defaultSectionOrder[section] ?? 999);
}

TextStyle sectionTextStyle(
  Entry config, {
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.normal,
}) => TextStyle(
  color: config.text('textColor').isEmpty
      ? null
      : colorFromHex(config.text('textColor'), Colors.black87),
  fontFamily: config.text('fontFamily').isEmpty
      ? null
      : config.text('fontFamily'),
  fontSize: config.number('fontSize') <= 0
      ? fontSize
      : clampedNumber(config, 'fontSize', fontSize, 10, 72),
  fontWeight: FontWeight.values.firstWhere(
    (weight) =>
        weight.value ==
        config.number('fontWeight', fontWeight.value.toDouble()),
    orElse: () => fontWeight,
  ),
  fontStyle: config.text('fontStyle') == 'italic'
      ? FontStyle.italic
      : FontStyle.normal,
);

BoxShadow? shadowFromEntry(Entry entry) {
  final strength = clampedNumber(entry, 'shadow', 0, 0, 1);
  if (strength == 0) return null;
  return BoxShadow(
    color: Colors.black.withValues(alpha: strength * .22),
    blurRadius: 18 * strength,
    offset: Offset(0, 6 * strength),
  );
}

BoxDecoration entryDecoration(
  Entry entry, {
  Color fallback = Colors.white,
  double defaultRadius = 20,
}) {
  final opacity = clampedNumber(entry, 'opacity', 1, 0, 1);
  final brightness = clampedNumber(entry, 'brightness', 1, 0.2, 2);
  final base = colorFromHex(entry.text('backgroundColor'), fallback);
  final background =
      (brightness <= 1
              ? Color.lerp(Colors.black, base, brightness)!
              : Color.lerp(base, Colors.white, brightness - 1)!)
          .withValues(alpha: base.a * opacity);
  final shadow = shadowFromEntry(entry);
  final imageUrl = entry.text('backgroundImage');
  return BoxDecoration(
    color: background,
    image: imageUrl.isEmpty
        ? null
        : DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 1 - brightness.clamp(0.2, 2) / 2),
              BlendMode.darken,
            ),
          ),
    borderRadius: BorderRadius.circular(
      clampedNumber(entry, 'radius', defaultRadius, 0, 80),
    ),
    border: entry.text('borderColor').isEmpty
        ? null
        : Border.all(
            color: colorFromHex(entry.text('borderColor'), Colors.transparent),
            width: clampedNumber(entry, 'borderWidth', 1, 0, 12),
          ),
    boxShadow: shadow == null ? null : [shadow],
  );
}

/// A product's precomputed `avgRating`/`reviewCount` (set server-side by
/// `submitVerifiedReview` from the real reviews subcollection — never
/// editable directly) rendered as full/half/empty stars. Renders nothing for
/// an unrated product rather than a row of empty stars.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.count = 0, this.size = 14});
  final double rating;
  final int count;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (rating <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star
                : rating >= i - 0.5
                ? Icons.star_half
                : Icons.star_border,
            size: size,
            color: AppTokens.accentGold,
          ),
        if (count > 0) ...[
          SizedBox(width: size * .3),
          Text(
            '($count)',
            style: TextStyle(fontSize: size * .85, color: AppTokens.textMuted),
          ),
        ],
      ],
    );
  }
}

void message(BuildContext context, Object text) => ScaffoldMessenger.of(context)
    .showSnackBar(
      SnackBar(content: Text(text.toString().replaceFirst('Bad state: ', ''))),
    );

class ProductArt extends StatelessWidget {
  const ProductArt(this.entry, {super.key, this.height = 160, this.width});
  final Entry entry;
  final double height;
  final double? width;
  @override
  Widget build(BuildContext context) {
    final icons = [
      Icons.eco_outlined,
      Icons.coffee_outlined,
      Icons.headphones_outlined,
      Icons.shopping_basket_outlined,
      Icons.plumbing,
      Icons.electrical_services,
      Icons.foundation,
      Icons.handyman_outlined,
    ];
    final index = int.tryParse(entry.id.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final placeholder = Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.tintFor(index),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Center(
        child: Container(
          padding: EdgeInsets.all(height * .12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .6),
            shape: BoxShape.circle,
            boxShadow: AppTokens.shadowSoft,
          ),
          child: Icon(
            icons[index % icons.length],
            size: height * .4,
            color: AppTokens.accentFor(index),
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: entry.text('imageUrl').isEmpty
          ? placeholder
          : Image.network(
              entry.text('imageUrl'),
              height: height,
              width: width ?? double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, e, s) => placeholder,
            ),
    );
  }
}

String money(num value) =>
    '₹${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}';
