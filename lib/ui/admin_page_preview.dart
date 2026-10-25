import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'admin_fields.dart';
import 'home_section_config.dart';

/// "Page view": the home page as a list of its sections, in the order customers see them. Tap one to edit it, drag its
/// handle to move it, use + / − to resize it. (Moved here unchanged from the old admin shell; opened from
/// Settings → Layout.)
class AdminPagePreview extends StatelessWidget {
  const AdminPagePreview({super.key, required this.store, required this.onOpenSection});
  final Store store;
  // Called with the section key (products, categories, scrollingText, ...) of the block that was tapped.
  final void Function(String section) onOpenSection;

  static const _resizeStep = 40.0;
  static const _maxSectionHeight = 1200.0;

  Future<void> _setSectionHeight(String layoutKey, double height) => adjustSectionHeight(store, layoutKey, height);

  Widget _block(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required String targetSection,
    String? layoutKey,
    int? reorderIndex,
    bool resizable = false,
  }) {
    final resizeKey = layoutKey ?? targetSection;
    final height = resizable ? sectionConfig(store.entries('settings'), resizeKey).number('height', 0) : 0.0;
    return Card(
      // Keyed by the unique layout/resize key, not targetSection: several layout keys (e.g. 'popular' and
      // 'localServices') can share one targetSection ('products'), which would collide inside the ReorderableListView.
      key: ValueKey(resizeKey),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          InkWell(
            onTap: () => onOpenSection(targetSection),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (reorderIndex != null)
                    ReorderableDragStartListener(
                      index: reorderIndex,
                      child: const Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.drag_indicator)),
                    ),
                  Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    avatar: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(adminSections[targetSection] ?? targetSection, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
          if (resizable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.height, size: 18),
                  const SizedBox(width: 8),
                  Text(height <= 0 ? 'Height: automatic' : 'Height: ${height.round()}px', style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Decrease size',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: height <= 0 ? null : () => _setSectionHeight(resizeKey, (height - _resizeStep).clamp(0, _maxSectionHeight)),
                  ),
                  IconButton(
                    tooltip: 'Increase size',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _setSectionHeight(resizeKey, ((height <= 0 ? 200 : height) + _resizeStep).clamp(0, _maxSectionHeight)),
                  ),
                  if (height > 0)
                    IconButton(
                      tooltip: 'Reset to automatic size',
                      icon: const Icon(Icons.settings_backup_restore),
                      onPressed: () => _setSectionHeight(resizeKey, 0),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Live-data subtitle for a section's preview block — the static title/icon/targetSection live on SectionDescriptor itself
  // (shared.dart), the single source of truth also read by WireframeHome; only this text needs data.
  String _subtitleFor(
    SectionDescriptor d, {
    required Entry? ticker,
    required List<Entry> categories,
    required List<Entry> products,
    required List<Entry> services,
    required List<Entry> promotions,
  }) {
    switch (d.key) {
      case 'notice':
        return (ticker?.text('text') ?? '').isEmpty ? 'No scrolling text set yet.' : ticker!.text('text');
      case 'categories':
        return categories.isEmpty ? 'No categories yet.' : categories.take(5).map((c) => c.text('name', c.id)).join(', ');
      case 'popular':
        return '${products.length} item(s) — ${products.take(3).map((p) => p.text('name', p.id)).join(', ')}';
      case 'promo':
        return promotions.isEmpty ? 'No promotions yet.' : '${promotions.length} entr${promotions.length == 1 ? 'y' : 'ies'}';
      case 'localServices':
        return services.isEmpty ? 'No services yet.' : '${services.length} service(s)';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final settings = store.entries('settings');
      final ticker = settings.where((e) => e.id == 'scrollingText').firstOrNull;
      final categories = store.entries('categories');
      final products = store.entries('products');
      final services = store.visibleServices(all: true);
      final promotions = store.entries('promotions');
      final shops = store.entries('shops');
      final orderedKeys = [...reorderableHomeSections]..sort((a, b) => sectionOrder(settings, a.key).compareTo(sectionOrder(settings, b.key)));
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'This mirrors what customers see on the site. Tap any section to edit it directly. '
            'Drag the handle to reorder a section top-to-bottom, use + / − to resize it.',
          ),
          const SizedBox(height: 16),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) => reorderHomeSections(store, oldIndex, newIndex),
            children: [
              for (final (index, descriptor) in orderedKeys.indexed)
                _block(
                  context,
                  title: descriptor.title,
                  subtitle: _subtitleFor(descriptor, ticker: ticker, categories: categories, products: products, services: services, promotions: promotions),
                  icon: descriptor.icon,
                  targetSection: descriptor.targetSection,
                  layoutKey: descriptor.key,
                  reorderIndex: index,
                  resizable: true,
                ),
            ],
          ),
          _block(
            context,
            title: 'Shops',
            subtitle: shops.isEmpty
                ? 'No shops yet.'
                : '${shops.take(3).map((s) => s.text('name', s.id)).join(', ')} — always shown inside Products on the site',
            icon: Icons.storefront_outlined,
            targetSection: 'shops',
          ),
        ],
      );
    },
  );
}
