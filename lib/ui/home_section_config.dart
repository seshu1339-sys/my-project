import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';

/// Home-page "section" configuration: which admin-reorderable sections exist
/// (promo/categories/popular/localServices), their stored order/height, and
/// visibility. Split out of shared.dart, which otherwise mixes this cohesive,
/// self-contained subsystem in with unrelated generic UI utilities
/// (colorFromHex, money, ProductArt, ...). Read and written by both the
/// admin shell's Page-view dashboard (admin.dart) and the Visual Editor
/// (visual_editor.dart/wireframe_home.dart) — this file is their shared
/// domain model, not a grab-bag of unrelated helpers.

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

Future<void> adjustSectionWidth(Store store, String layoutKey, double width) =>
    adjustSectionField(store, layoutKey, 'width', width);

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

// Elements that should start OFF until an admin explicitly turns them on,
// unlike every other component (which defaults to visible -- see
// sectionVisible above). Kept to a named, deliberately short list rather
// than a per-component field, since "hidden by default" is the unusual
// case.
const _defaultHiddenComponents = {'adsLabel'};

/// Like [sectionVisible], but respects a component's own default (most
/// default to shown; [_defaultHiddenComponents] default to hidden) when the
/// admin hasn't explicitly set 'visible' either way. Both the renderer and
/// the admin form's own toggle call this (never [sectionVisible] directly
/// for one of these components), so what the toggle shows and what
/// actually renders can never disagree.
bool componentVisible(Entry config, String component) =>
    _defaultHiddenComponents.contains(component)
    ? (config.data['visible'] == 'true' || config.data['visible'] == true)
    : sectionVisible(config);

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
