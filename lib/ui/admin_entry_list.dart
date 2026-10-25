import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'admin_fields.dart';
import 'admin_list_labels.dart';
import 'entry_editor.dart';
import 'shared.dart';

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

/// The collections whose records have an order number the site follows; their lists can be dragged into a new order.
const _orderedSections = {'products', 'services', 'categories', 'promotions', 'shops'};

/// A setting that exists once (Business Profile, Theme, Scrolling Text): its form, straight away. A project that has never saved it
/// gets the same form, empty, and the first Save creates it.
class AdminSingleRecord extends StatelessWidget {
  const AdminSingleRecord({super.key, required this.store, required this.section});
  final Store store;
  final String section;

  static String recordId(String section) => section == 'settings' ? 'business' : section;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final Entry? record = store.entries('settings').where((e) => e.id == recordId(section)).firstOrNull;
      // Keyed by "exists yet": the form is rebuilt once when the first Save creates the record.
      return EntryEditor(key: ValueKey('single-$section-${record != null}'), store: store, collection: section, entry: record, embedded: true);
    },
  );
}

/// One admin collection as a list: its records, "Add new", edit / delete on every row, and (for products, categories, promotions
/// and shops) drag-to-reorder and "Renumber". Products also get a search box, filters and bulk "Assign shop". [section] is a
/// key of `adminSections`.
class AdminEntryList extends StatefulWidget {
  const AdminEntryList({super.key, required this.store, required this.section, this.placement});
  final Store store;
  final String section;
  // Promotions only: show just one kind (carousel = Today's Offers Box, box = the boxes below the ads) and start new ones as that kind.
  final String? placement;
  @override
  State<AdminEntryList> createState() => _AdminEntryListState();
}

class _AdminEntryListState extends State<AdminEntryList> {
  Store get store => widget.store;
  String get section => widget.section;

  final search = TextEditingController();
  bool noShopOnly = false;
  // Products: only the items vendors added themselves (they have an owner).
  bool vendorItemsOnly = false;
  String? categoryId;
  String status = 'all'; // all | published | draft
  bool selecting = false;
  final selected = <String>{};

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  bool get _filtered => search.text.trim().isNotEmpty || noShopOnly || vendorItemsOnly || categoryId != null || status != 'all';

  Future<void> _edit(Entry? entry) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => EntryEditor(store: store, collection: section, entry: entry, initialPlacement: widget.placement)),
  );

  Future<void> _remove(Entry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove ${entry.text('name', entry.id)} permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
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
          await FirebaseStorage.instance.refFromURL(entry.text('imageUrl')).delete();
        } catch (_) {
          // Best-effort: an already-missing or unreachable object must not block deleting the entry.
        }
      }
      await store.delete(section, entry.id);
      if (mounted) message(context, 'Deleted');
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> _write(Map<String, Map<String, dynamic>> changes, String done) async {
    try {
      await store.updateMany(section, changes);
      if (mounted) message(context, done);
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> _assignShop(List<Entry> chosen) async {
    final shops = store.entries('shops');
    String? shopId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: Text('Assign a shop to ${chosen.length} ${chosen.length == 1 ? 'product' : 'products'}'),
          content: DropdownButtonFormField<String>(
            key: const ValueKey('assign-shop-dropdown'),
            initialValue: shopId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Shop'),
            items: [for (final s in shops) DropdownMenuItem(value: s.id, child: Text(s.text('name', s.id)))],
            onChanged: (v) => setState(() => shopId = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(
              key: const ValueKey('assign-shop-confirm'),
              onPressed: shopId == null ? null : () => Navigator.pop(dialog, true),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || shopId == null) return;
    final name = shops.firstWhere((s) => s.id == shopId).text('name', shopId!);
    await _write({for (final p in chosen) p.id: {'shopId': shopId}}, '${chosen.length} ${chosen.length == 1 ? 'product' : 'products'} now belong to $name');
    if (mounted) setState(selected.clear);
  }

  /// The records to show, after the search box and filters (products only).
  List<Entry> _visible(List<Entry> sorted) {
    if (section == 'promotions' && widget.placement != null) return [for (final p in sorted) if (p.text('placement') == widget.placement) p];
    if (section != 'products') return sorted;
    final categories = {for (final c in store.entries('categories')) c.id: c.text('name', c.id).toLowerCase()};
    final shops = {for (final s in store.entries('shops')) s.id: s.text('name', s.id).toLowerCase()};
    final shopIds = shops.keys.toSet();
    final q = search.text.trim().toLowerCase();
    return [
      for (final p in sorted)
        if ((q.isEmpty ||
                p.text('name').toLowerCase().contains(q) ||
                p.text('tags').toLowerCase().contains(q) ||
                (categories[p.text('categoryId')] ?? '').contains(q) ||
                (shops[p.text('shopId')] ?? '').contains(q)) &&
            (!noShopOnly || productProblems(p, shopIds: shopIds).contains('No shop')) &&
            (!vendorItemsOnly || p.text('ownerId').isNotEmpty) &&
            (categoryId == null || p.text('categoryId') == categoryId) &&
            (status == 'all' || (status == 'published') == p.active))
          p,
    ];
  }

  String _subtitle(Entry e) {
    final order = 'Order ${e.number('order').toInt()}';
    final state = e.active ? 'Published' : 'Hidden';
    switch (section) {
      case 'promotions':
        return '${promotionStatusLabel(e)} • ${promotionPlacementLabel(e)} • $order'
            ' • Location: ${promotionLocationLabel(e)} • ${_promotionAreaLabel(e)}';
      case 'products':
        final categories = {for (final c in store.entries('categories')) c.id: c.text('name', c.id)};
        final shops = {for (final s in store.entries('shops')) s.id: s.text('name', s.id)};
        final problems = productProblems(
          e,
          categoryIds: categories.keys.toSet(),
          shopIds: shops.keys.toSet(),
        ).where((p) => p != 'No shop').toList();
        final shop = shops[e.text('shopId')];
        return [
          state,
          if (e.text('kind') == 'service') 'Service',
          if (categories[e.text('categoryId')] != null) categories[e.text('categoryId')]!,
          if (shop != null) shop else if (e.text('kind') != 'service') 'No shop',
          order,
          if (problems.isNotEmpty) '⚠ ${problems.join(', ')}',
        ].join(' • ');
      case 'services':
        final shopName = store.entries('shops').where((s) => s.id == e.text('shopId')).firstOrNull?.text('name');
        return [state, e.text('kind') == 'serviceType' ? 'Service type' : 'Service listing', ?shopName, order].join(' • ');
      default:
        return '$state • $order';
    }
  }

  String _title(Entry e) {
    final name = e.text('name', adminSections[section] ?? section);
    if (section != 'promotions') return name;
    // Two promotions can share a headline; what each one leads to tells them apart.
    final label = promotionTargetLabel(
      e,
      categories: {for (final c in store.entries('categories')) c.id: c.text('name', c.id)},
      products: {for (final p in store.entries('products')) p.id: p.text('name', p.id)},
      shops: {for (final s in store.entries('shops')) s.id: s.text('name', s.id)},
    );
    return '$name — $label';
  }

  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            key: const ValueKey('product-search'),
            controller: search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search products', isDense: true, border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ),
        FilterChip(
          key: const ValueKey('filter-no-shop'),
          label: const Text('No shop only'),
          selected: noShopOnly,
          onSelected: (v) => setState(() => noShopOnly = v),
        ),
        FilterChip(
          key: const ValueKey('filter-vendor-items'),
          label: const Text('Vendor items'),
          selected: vendorItemsOnly,
          onSelected: (v) => setState(() => vendorItemsOnly = v),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            key: const ValueKey('filter-category'),
            initialValue: categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category', isDense: true, border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
              for (final c in sortedByOrder(store.entries('categories'))) DropdownMenuItem<String?>(value: c.id, child: Text(c.text('name', c.id))),
            ],
            onChanged: (v) => setState(() => categoryId = v),
          ),
        ),
        SegmentedButton<String>(
          key: const ValueKey('filter-status'),
          segments: const [
            ButtonSegment(value: 'all', label: Text('All')),
            ButtonSegment(value: 'published', label: Text('Published')),
            ButtonSegment(value: 'draft', label: Text('Draft')),
          ],
          selected: {status},
          onSelectionChanged: (s) => setState(() => status = s.first),
        ),
        if (_filtered)
          TextButton(
            onPressed: () => setState(() {
              search.clear();
              noShopOnly = false;
              vendorItemsOnly = false;
              categoryId = null;
              status = 'all';
            }),
            child: const Text('Clear filters'),
          ),
      ],
    ),
  );

  Widget _selectionBar(List<Entry> shown) => Container(
    color: Theme.of(context).colorScheme.secondaryContainer,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${selected.length} selected', key: const ValueKey('selected-count'), style: const TextStyle(fontWeight: FontWeight.bold)),
        TextButton(
          key: const ValueKey('select-all'),
          onPressed: () => setState(() => selected.addAll(shown.map((e) => e.id))),
          child: Text('Select all ${shown.length} shown'),
        ),
        FilledButton.icon(
          key: const ValueKey('assign-shop'),
          onPressed: selected.isEmpty ? null : () => _assignShop([for (final e in shown) if (selected.contains(e.id)) e]),
          icon: const Icon(Icons.storefront_outlined),
          label: const Text('Assign shop'),
        ),
        TextButton(onPressed: () => setState(() => selected.clear()), child: const Text('Clear')),
        TextButton(onPressed: () => setState(() { selecting = false; selected.clear(); }), child: const Text('Done')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      // Services have their own list (the Services tab); a service record still sitting in products is not shown in Products.
      final all = sortedByOrder([for (final e in store.entries(section)) if (section != 'products' || e.text('kind') != 'service') e]);
      final shown = _visible(all);
      final reorderable = _orderedSections.contains(section) && !_filtered && !selecting;
      final untidy = _orderedSections.contains(section) && hasUntidyOrder(all);
      Widget row(Entry e, int i) => Card(
        key: ValueKey(e.id),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        child: ListTile(
          leading: selecting
              ? Checkbox(
                  key: ValueKey('select-${e.id}'),
                  value: selected.contains(e.id),
                  onChanged: (v) => setState(() => v == true ? selected.add(e.id) : selected.remove(e.id)),
                )
              : reorderable
              ? ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator))
              : Icon(e.active ? Icons.check_circle_outline : Icons.pause_circle_outline),
          title: Text(_title(e)),
          subtitle: Text(_subtitle(e)),
          trailing: Wrap(
            spacing: 2,
            children: [
              IconButton(tooltip: 'Delete', onPressed: () => _remove(e), icon: const Icon(Icons.delete_outline)),
              const Icon(Icons.edit_outlined),
            ],
          ),
          onTap: selecting
              ? () => setState(() => selected.contains(e.id) ? selected.remove(e.id) : selected.add(e.id))
              : () => _edit(e),
        ),
      );
      return Column(
        children: [
          if (!store.live)
            Container(
              width: double.infinity,
              color: const Color(0xffffedcb),
              padding: const EdgeInsets.all(12),
              child: const Text('Demo studio • Changes are saved on this device. Live access requires an administrator account.'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              spacing: 8,
              children: [
                Text(
                  _filtered ? '${shown.length} of ${all.length} $section' : '${all.length} $section',
                  key: const ValueKey('list-count'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (section == 'products' && all.isNotEmpty)
                      OutlinedButton.icon(
                        key: const ValueKey('toggle-select'),
                        onPressed: () => setState(() {
                          selecting = !selecting;
                          selected.clear();
                        }),
                        icon: const Icon(Icons.checklist),
                        label: Text(selecting ? 'Stop selecting' : 'Select several'),
                      ),
                    FilledButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('Add new')),
                  ],
                ),
              ],
            ),
          ),
          if (section == 'products') _filters(),
          if (untidy)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Card(
                key: const ValueKey('untidy-order'),
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.format_list_numbered),
                  title: const Text('Some order numbers are repeated or skip a number.'),
                  subtitle: const Text('Renumber gives every record its own number, 1, 2, 3 ..., in the order shown. You can also drag a row to move it.'),
                  trailing: FilledButton(
                    key: const ValueKey('renumber'),
                    onPressed: () => _write(renumberChanges(all), 'Numbered 1 to ${all.length}'),
                    child: const Text('Renumber'),
                  ),
                ),
              ),
            ),
          if (selecting) _selectionBar(shown),
          const SizedBox(height: 12),
          Expanded(
            child: all.isEmpty
                ? const Center(child: Text('Start by adding your first item.'))
                : shown.isEmpty
                ? const Center(child: Text('Nothing matches. Clear the search or filters.'))
                : reorderable
                ? ReorderableListView.builder(
                    key: const ValueKey('reorderable-list'),
                    buildDefaultDragHandles: false,
                    itemCount: shown.length,
                    itemBuilder: (context, i) => row(shown[i], i),
                    onReorderItem: (oldIndex, newIndex) => _write(reorderChanges(all, oldIndex, newIndex), 'Order saved'),
                  )
                : ListView.builder(itemCount: shown.length, itemBuilder: (context, i) => row(shown[i], i)),
          ),
        ],
      );
    },
  );
}

/// An [AdminEntryList] (or, for a single-record setting, its form) as a page of its own: reached from the Page view.
class AdminEntryListPage extends StatelessWidget {
  const AdminEntryListPage({super.key, required this.store, required this.section});
  final Store store;
  final String section;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(adminSections[section] ?? section)),
    body: const {'settings', 'theme', 'scrollingText'}.contains(section)
        ? AdminSingleRecord(store: store, section: section)
        : AdminEntryList(store: store, section: section),
  );
}
