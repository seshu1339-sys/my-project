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

/// " • ⚠ No shop, No photo" appended to a product's list line when it is incomplete.
String _productProblemsSuffix(Entry product, Store store) {
  final problems = productProblems(
    product,
    categoryIds: {for (final c in store.entries('categories')) c.id},
    shopIds: {for (final s in store.entries('shops')) s.id},
  );
  return problems.isEmpty ? '' : ' • ⚠ ${problems.join(', ')}';
}

/// One admin collection as a list: its records, "Add new", and edit / delete on every row. [section] is a key of
/// `adminSections` (products, categories, shops, promotions, settings = Business profile, scrollingText, theme, ...).
class AdminEntryList extends StatelessWidget {
  const AdminEntryList({super.key, required this.store, required this.section});
  final Store store;
  final String section;

  Future<void> _edit(BuildContext context, Entry? entry) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EntryEditor(store: store, collection: section, entry: entry),
    ),
  );

  Future<void> _remove(BuildContext context, Entry entry) async {
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
      await store.delete(section == 'scrollingText' || section == 'theme' ? 'settings' : section, entry.id);
      if (context.mounted) message(context, 'Deleted');
    } catch (e) {
      if (context.mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final entries = store
          .entries(section == 'scrollingText' || section == 'theme' ? 'settings' : section)
          .where(
            (entry) => section == 'settings'
                ? entry.id == 'business'
                : section != 'scrollingText' && section != 'theme' || entry.id == section,
          )
          .toList();
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${entries.length} ${section == 'settings' ? 'business profiles' : section}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: section == 'settings' && entries.isNotEmpty ? null : () => _edit(context, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add new'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('Start by adding your first item.'))
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                        child: ListTile(
                          leading: Icon(e.active ? Icons.check_circle_outline : Icons.pause_circle_outline),
                          title: Text(e.text('name')),
                          subtitle: Text(
                            section == 'promotions'
                                ? '${e.id} • ${promotionStatusLabel(e)} • Order ${e.number('order').toInt()}'
                                      ' • Location: ${promotionLocationLabel(e)}'
                                      ' • ${_promotionAreaLabel(e)}'
                                : '${e.id} • ${e.active ? 'Published' : 'Hidden'} • Order ${e.number('order').toInt()}'
                                      '${section == 'products' ? _productProblemsSuffix(e, store) : ''}',
                          ),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: section == 'settings' ? null : () => _remove(context, e),
                                icon: const Icon(Icons.delete_outline),
                              ),
                              const Icon(Icons.edit_outlined),
                            ],
                          ),
                          onTap: () => _edit(context, e),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}

/// An [AdminEntryList] as a page of its own (reached from a Settings section or the Page view).
class AdminEntryListPage extends StatelessWidget {
  const AdminEntryListPage({super.key, required this.store, required this.section});
  final Store store;
  final String section;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(adminSections[section] ?? section)),
    body: AdminEntryList(store: store, section: section),
  );
}
