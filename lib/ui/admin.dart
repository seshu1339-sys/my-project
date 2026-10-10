import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/admin_route.dart';
import 'shared.dart';
import 'layout_editor.dart';
import 'visual_editor.dart';
import 'admin_insights.dart';
import 'field_moderation.dart';

// admin.dart is the admin shell (AdminPage/_AdminPageState: chip nav, the
// drag-reorder "Page view" preview, and routing to the pages below). Each
// moderation/editing concern lives in its own file with no shared private
// helpers between them (verified: VendorModerationPage, ComplaintModeration-
// Page, AdminOrders and EntryEditor share nothing but Store/Entry/shared.dart
// — each is independently updatable). Exported (not just imported) so that
// existing code importing only 'admin.dart' — main_admin.dart, admin_auth.dart,
// and test/admin_test.dart's direct `EntryEditor` usage — keeps working
// unchanged; the public symbol set is identical to before this split.
import 'admin_fields.dart';
import 'admin_orders.dart';
import 'complaint_moderation.dart';
import 'entry_editor.dart';
import 'vendor_moderation.dart';
import 'admin_search.dart';
import 'ai_agent_page.dart';
export 'admin_fields.dart';
export 'admin_orders.dart';
export 'complaint_moderation.dart';
export 'entry_editor.dart';
export 'vendor_moderation.dart';
export 'admin_search.dart';
export 'ai_agent_page.dart';

String _promotionAreaLabel(Entry promotion) {
  final shape = promotion.text('geoShape', 'circle');
  if (shape == 'rectangle') {
    return parseRectangleField(promotion.data['targetRectangle']) != null ? 'Rectangle area' : 'No area targeting';
  }
  if (shape == 'polygon') {
    return parsePolygonField(promotion.data['targetPolygon']) != null ? 'Polygon area' : 'No area targeting';
  }
  return (promotion.number('targetLatitude') != 0 || promotion.number('targetLongitude') != 0)
      ? 'Circle area'
      : 'No area targeting';
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String section = 'products';
  bool pageView = false;

  @override
  void initState() {
    super.initState();
    // A Home Screen shortcut to `<admin route>?open=ai-agent` lands here
    // straight after the normal password+OTP login; this is the only effect
    // of that query param — nothing about login itself changes. Scheduled
    // for after the first frame since Navigator needs a built context.
    if (wantsAiAgentDirectly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AiAgentPage(store: widget.store)));
      });
    }
  }

  // Sections that correspond to something the customer actually sees on the
  // page, in roughly the order it appears there. Anything not listed here
  // (business profile, theme, section customization, the image library) has
  // no single on-page spot to click, so it only lives behind the gear menu.
  static const _onPageSections = ['scrollingText', 'categories', 'products', 'promotions', 'shops'];

  static const _resizeStep = 40.0;
  static const _maxSectionHeight = 1200.0;

  Future<void> _setSectionHeight(String layoutKey, double height) =>
      adjustSectionHeight(widget.store, layoutKey, height);

  Widget _pagePreviewBlock(
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
    final height = resizable
        ? sectionConfig(widget.store.entries('settings'), resizeKey).number('height', 0)
        : 0.0;
    return Card(
      // Keyed by the unique layout/resize key, not targetSection — several
      // layout keys (e.g. 'popular' and 'localServices') can legitimately
      // share the same targetSection ('products'), which would otherwise
      // collide as a duplicate GlobalKey inside the ReorderableListView.
      key: ValueKey(resizeKey),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              section = targetSection;
              pageView = false;
            }),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (reorderIndex != null)
                    ReorderableDragStartListener(
                      index: reorderIndex,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(Icons.drag_indicator),
                      ),
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
                  Text(
                    height <= 0 ? 'Height: automatic' : 'Height: ${height.round()}px',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Decrease size',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: height <= 0
                        ? null
                        : () => _setSectionHeight(resizeKey, (height - _resizeStep).clamp(0, _maxSectionHeight)),
                  ),
                  IconButton(
                    tooltip: 'Increase size',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _setSectionHeight(
                      resizeKey,
                      ((height <= 0 ? 200 : height) + _resizeStep).clamp(0, _maxSectionHeight),
                    ),
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

  Future<void> _reorderSections(int oldIndex, int newIndex) =>
      reorderHomeSections(widget.store, oldIndex, newIndex);

  // Live-data subtitle for a section's Page view preview block — the static
  // title/icon/targetSection live on SectionDescriptor itself (shared.dart),
  // the single source of truth also read by WireframeHome; only this preview
  // text needs data (category/product counts) unavailable there.
  String _subtitleFor(SectionDescriptor d, {
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

  Widget _pagePreview(BuildContext context) {
    final settings = widget.store.entries('settings');
    final ticker = settings.where((e) => e.id == 'scrollingText').firstOrNull;
    final categories = widget.store.entries('categories');
    final products = widget.store.entries('products');
    final services = products.where((p) => p.text('kind') == 'service').toList();
    final promotions = widget.store.entries('promotions');
    final shops = widget.store.entries('shops');
    final orderedKeys = [...reorderableHomeSections]
      ..sort((a, b) => sectionOrder(settings, a.key).compareTo(sectionOrder(settings, b.key)));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'This mirrors what customers see on the site. Tap any section to edit it directly. '
          'Drag the handle to reorder a section top-to-bottom, use + / − to resize it. '
          'Anything not shown here (business profile, theme, section sizing) is under the gear icon above.',
        ),
        const SizedBox(height: 16),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) => _reorderSections(oldIndex, newIndex),
          children: [
            for (final (index, descriptor) in orderedKeys.indexed)
              _pagePreviewBlock(
                context,
                title: descriptor.title,
                subtitle: _subtitleFor(
                  descriptor,
                  ticker: ticker,
                  categories: categories,
                  products: products,
                  services: services,
                  promotions: promotions,
                ),
                icon: descriptor.icon,
                targetSection: descriptor.targetSection,
                layoutKey: descriptor.key,
                reorderIndex: index,
                resizable: true,
              ),
          ],
        ),
        _pagePreviewBlock(
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
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      if (widget.store.live && !widget.store.admin) {
        return Scaffold(
          appBar: AppBar(title: const Text('Admin')),
          body: const Center(
            child: Text(
              'Sign in with an administrator account to manage your business.',
            ),
          ),
        );
      }
      final entries = widget.store
          .entries(
            section == 'scrollingText' ||
                    section == 'theme' ||
                    section == 'sectionSettings'
                ? 'settings'
                : section,
          )
          .where(
            (entry) => section == 'settings'
                ? entry.id == 'business'
                : section == 'sectionSettings'
                ? entry.id.startsWith('section_')
                : section != 'scrollingText' && section != 'theme' ||
                      entry.id == section,
          )
          .toList();
      final navTargets = <String, (IconData, WidgetBuilder)>{
        'Orders': (Icons.receipt_long, (_) => AdminOrders(store: widget.store)),
        'Vendors': (Icons.storefront, (_) => VendorModerationPage(store: widget.store)),
        'Field Assistants': (Icons.badge_outlined, (_) => FieldModerationPage(store: widget.store)),
        'Complaints': (Icons.report_problem_outlined, (_) => ComplaintModerationPage(store: widget.store)),
        'Insights': (Icons.insights, (_) => AdminInsightsPage(store: widget.store)),
        'Search': (Icons.search, (_) => AdminSearchPage(store: widget.store)),
        'AI Agent': (Icons.smart_toy_outlined, (_) => AiAgentPage(store: widget.store)),
      };
      void openNav(String label) => Navigator.push(context, MaterialPageRoute<void>(builder: navTargets[label]!.$2));
      // Below ~1300px, the AppBar actions (page view toggle, other-settings menu, layout
      // settings, sign out, plus the 7 nav buttons including AI Agent) would overflow;
      // collapse the navigation buttons into one menu there and keep today's full row on
      // wider screens. A RenderFlex overflow here clips silently in release builds (no
      // debug stripes), so this threshold must stay ahead of the actual content width,
      // not just "look wide enough" — raised from 1100 when AI Agent became the 7th button.
      final narrow = MediaQuery.sizeOf(context).width < 1300;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Business studio'),
          actions: [
            IconButton(
              tooltip: pageView ? 'Switch to list view' : 'Switch to page view (click a section to edit it)',
              icon: Icon(pageView ? Icons.list_alt_outlined : Icons.view_agenda_outlined),
              onPressed: () => setState(() => pageView = !pageView),
            ),
            PopupMenuButton<String>(
              tooltip: 'Other settings (not shown on the page)',
              icon: const Icon(Icons.settings_outlined),
              onSelected: (value) => setState(() {
                section = value;
                pageView = false;
              }),
              itemBuilder: (context) => [
                for (final key in adminSections.keys)
                  if (!_onPageSections.contains(key))
                    PopupMenuItem(value: key, child: Text(adminSections[key]!)),
              ],
            ),
            IconButton(
              tooltip: 'UI Customization / Layout Settings',
              icon: const Icon(Icons.dashboard_customize_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => LayoutSettingsPage(store: widget.store),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Visual Editor — click a section on the live preview to edit it',
              icon: const Icon(Icons.auto_fix_high_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => VisualEditorPage(store: widget.store),
                ),
              ),
            ),
            if (widget.store.live)
              TextButton.icon(
                onPressed: widget.store.logout,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            if (narrow)
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: openNav,
                itemBuilder: (context) => [
                  for (final entry in navTargets.entries)
                    PopupMenuItem(value: entry.key, child: Row(children: [Icon(entry.value.$1, size: 20), const SizedBox(width: 12), Text(entry.key)])),
                ],
              )
            else
              for (final label in navTargets.keys)
                TextButton.icon(onPressed: () => openNav(label), icon: Icon(navTargets[label]!.$1), label: Text(label)),
          ],
        ),
        body: pageView ? _pagePreview(context) : Column(
          children: [
            if (!widget.store.live)
              Container(
                width: double.infinity,
                color: const Color(0xffffedcb),
                padding: const EdgeInsets.all(12),
                child: const Text(
                  'Demo studio • Changes are saved on this device. Live access requires an administrator account.',
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in adminSections.keys)
                      ChoiceChip(
                        label: Text(adminSections[item]!),
                        selected: section == item,
                        onSelected: (_) => setState(() => section = item),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entries.length} ${section == 'settings' ? 'business profiles' : section}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: section == 'settings' && entries.isNotEmpty
                        ? null
                        : () => edit(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add new'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text('Start by adding your first item.'),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 5,
                          ),
                          child: ListTile(
                            leading: Icon(
                              e.active
                                  ? Icons.check_circle_outline
                                  : Icons.pause_circle_outline,
                            ),
                            title: Text(e.text('name')),
                            subtitle: Text(
                              '${e.id} • ${e.active ? 'Published' : 'Hidden'} • Order ${e.number('order').toInt()}'
                              '${section == 'promotions' ? ' • ${_promotionAreaLabel(e)}' : ''}',
                            ),
                            trailing: Wrap(
                              spacing: 2,
                              children: [
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: section == 'settings'
                                      ? null
                                      : () => remove(e),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                                const Icon(Icons.edit_outlined),
                              ],
                            ),
                            onTap: () => edit(e),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
  Future<void> edit(Entry? entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EntryEditor(store: widget.store, collection: section, entry: entry),
      ),
    );
  }

  Future<void> remove(Entry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove ${entry.text('name', entry.id)} permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      // The library is the one collection whose sole purpose is holding an image; deleting the
      // entry without its Storage object would immediately orphan it (the daily cleanup would
      // eventually catch it too, but there is no reason to wait).
      if (section == 'productImageLibrary' && entry.text('imageUrl').isNotEmpty) {
        try {
          await FirebaseStorage.instance
              .refFromURL(entry.text('imageUrl'))
              .delete();
        } catch (_) {
          // Best-effort: an already-missing or unreachable object must not block deleting the entry.
        }
      }
      await widget.store.delete(
        section == 'scrollingText' ||
                section == 'theme' ||
                section == 'sectionSettings'
            ? 'settings'
            : section,
        entry.id,
      );
      if (mounted) message(context, 'Deleted');
    } catch (e) {
      if (mounted) message(context, e);
    }
  }
}

