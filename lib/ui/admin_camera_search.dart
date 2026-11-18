import 'package:cloud_firestore/cloud_firestore.dart' show FieldPath;
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/camera_search.dart';
import '../domain/catalog.dart';
import 'shared.dart';

/// One counted camera search result of the last 30 days: the phone's label, what opened, how many times.
class CameraCount {
  const CameraCount(this.label, this.opened, this.count);
  final String label, opened;
  final int count;
}

/// Adds up the `camera_label` usage records (usageDaily/`day`~camera_label, functions/usage.js): one line per label and result,
/// most first.
List<CameraCount> cameraCountsOf(List<Map<String, dynamic>> days) {
  final totals = <String, int>{};
  for (final day in days) {
    final keys = day['keys'];
    if (keys is! Map) continue;
    for (final v in keys.values) {
      if (v is! Map) continue;
      final key = '${v['key'] ?? ''}';
      if (!key.contains('|')) continue;
      totals[key] = (totals[key] ?? 0) + ((v['count'] as num?)?.toInt() ?? 0);
    }
  }
  return [
    for (final e in totals.entries) CameraCount(e.key.substring(0, e.key.indexOf('|')), e.key.substring(e.key.indexOf('|') + 1), e.value),
  ]..sort((a, b) => b.count.compareTo(a.count));
}

/// Settings > Camera search (owner, 18 Nov 2026: cost cuts part 1). The phone names what is in a photo (ML Kit, free, offline) and
/// this table says what each name opens. Saved to settings/cameraSearch {aiAllowed, rows}; the app uses it from its next open.
///   "Camera search may use AI": off by default. On, the old AI photo search runs only when the names matched nothing (inside the
///   daily AI limit).
///   What people got: the counts of the last 30 days (label -> what opened). "none" and "chose" lines show labels worth adding.
class AdminCameraSearchPage extends StatefulWidget {
  const AdminCameraSearchPage({super.key, required this.store, this.loadDays});
  final Store store;

  /// Test seam: the usageDaily camera_label records of the last 30 days.
  final Future<List<Map<String, dynamic>>> Function()? loadDays;
  @override
  State<AdminCameraSearchPage> createState() => _AdminCameraSearchPageState();
}

class _Row {
  _Row(String label, this.categoryId, this.itemId) : label = TextEditingController(text: label);
  final TextEditingController label;
  String categoryId, itemId;
}

class _AdminCameraSearchPageState extends State<AdminCameraSearchPage> {
  Store get store => widget.store;
  late bool aiAllowed;
  late List<_Row> rows;
  bool busy = false;
  Future<List<CameraCount>>? counts;

  @override
  void initState() {
    super.initState();
    final settings = cameraSettingsOf(store.entries('settings'));
    aiAllowed = cameraAiAllowed(settings);
    rows = [for (final r in cameraRowsOf(settings)) _Row(r.label, r.categoryId, r.itemId)];
    counts = _loadCounts();
  }

  @override
  void dispose() {
    for (final r in rows) {
      r.label.dispose();
    }
    super.dispose();
  }

  Future<List<CameraCount>> _loadCounts() async {
    if (widget.loadDays != null) return cameraCountsOf(await widget.loadDays!());
    if (!store.live) return const [];
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final ids = [for (var i = 0; i < 30; i++) '${now.subtract(Duration(days: i)).toIso8601String().substring(0, 10)}~camera_label'];
    final snapshot = await store.firestore.collection('usageDaily').where(FieldPath.documentId, whereIn: ids).get();
    return cameraCountsOf([for (final d in snapshot.docs) d.data()]);
  }

  void _add([String label = '', String categoryId = '']) => setState(() => rows.add(_Row(label, categoryId, '')));

  Future<void> _save() async {
    final clean = <CameraRow>[];
    for (final r in rows) {
      final label = r.label.text.trim();
      if (label.isEmpty && r.categoryId.isEmpty && r.itemId.isEmpty) continue;
      if (label.isEmpty || (r.categoryId.isEmpty && r.itemId.isEmpty)) {
        message(context, 'Each row needs a camera label and a category or an item.');
        return;
      }
      clean.add(CameraRow(label, categoryId: r.categoryId, itemId: r.itemId));
    }
    setState(() => busy = true);
    try {
      final fields = {'aiAllowed': aiAllowed, 'rows': [for (final r in clean) r.toMap()]};
      await store.updateFields('settings', cameraSearchSettingsId, fields, fallback: Entry(cameraSearchSettingsId, {'name': 'Camera search', ...fields}));
      if (mounted) message(context, 'Saved. The app uses it from its next open.');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = [for (final c in store.entries('categories')) if (c.text('name').isNotEmpty) c];
    final items = [for (final i in store.entries('productImageLibrary')) if (i.text('name').isNotEmpty) i]
      ..sort((a, b) => a.text('name').compareTo(b.text('name')));
    String categoryName(String id) => categories.where((c) => c.id == id).firstOrNull?.text('name') ?? id;
    String opened(String value) {
      if (value.startsWith('category:')) return 'opened ${categoryName(value.substring(9))}';
      if (value.startsWith('chose:')) return 'nothing matched, they chose ${categoryName(value.substring(6))}';
      if (value.startsWith('item:')) return 'opened the item ${value.substring(5)}';
      if (value == 'ai') return 'AI search';
      return 'nothing matched, they chose nothing';
    }

    return ListView(
      key: const ValueKey('admin-camera-search'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Camera search', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'The phone names what is in the photo (Google ML Kit, free, the photo never leaves the phone), in English: for example '
          'Vegetable, Fruit, Shirt, Jewellery. An item name or Telugu word of the Item Catalog opens that item. Else this table '
          'decides the category. If nothing matches, the customer sees every category button. The camera button is in the app only.',
        ),
        SwitchListTile(
          key: const ValueKey('camera-ai-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Camera search may use AI'),
          subtitle: const Text('Off: no AI cost. On: AI looks at the photo only when nothing matched (inside the daily AI limit).'),
          value: aiAllowed,
          onChanged: (v) => setState(() => aiAllowed = v),
        ),
        const Divider(),
        Text('Camera labels → Category', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (i, r) in rows.indexed)
          Padding(
            key: ValueKey('camera-row-$i'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    key: ValueKey('camera-label-$i'),
                    controller: r.label,
                    decoration: const InputDecoration(labelText: 'Camera label', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('camera-category-$i'),
                    initialValue: categories.any((c) => c.id == r.categoryId) ? r.categoryId : '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('—')),
                      for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.text('name'), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => r.categoryId = v ?? ''),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('camera-item-$i'),
                    initialValue: items.any((it) => it.id == r.itemId) ? r.itemId : '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Or one item (optional)', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('—')),
                      for (final it in items) DropdownMenuItem(value: it.id, child: Text(it.text('name'), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => r.itemId = v ?? ''),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove row',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => rows.removeAt(i).label.dispose()),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(key: const ValueKey('camera-add-row'), onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add row')),
            TextButton(
              onPressed: () => setState(() {
                for (final r in rows) {
                  r.label.dispose();
                }
                rows = [for (final r in defaultCameraRows) _Row(r.label, r.categoryId, r.itemId)];
              }),
              child: const Text('Back to the starting table'),
            ),
            FilledButton(key: const ValueKey('camera-save'), onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
          ],
        ),
        const Divider(height: 32),
        Text('What people got (last 30 days)', style: Theme.of(context).textTheme.titleMedium),
        const Text('Only counts are kept, never the photo. Add a row for a label that matched nothing.'),
        const SizedBox(height: 8),
        FutureBuilder<List<CameraCount>>(
          future: counts,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('The counts could not load.');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final list = snapshot.data!;
            if (list.isEmpty) return const Text('No camera searches yet.');
            return Column(
              children: [
                for (final c in list.take(100))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${c.label} → ${opened(c.opened)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${c.count}'),
                        if (c.label != '-' && (c.opened == 'none' || c.opened.startsWith('chose:')))
                          TextButton(
                            onPressed: () => _add(c.label, c.opened.startsWith('chose:') ? c.opened.substring(6) : ''),
                            child: const Text('Add to table'),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
