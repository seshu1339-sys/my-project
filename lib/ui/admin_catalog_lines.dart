import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/catalog_lines.dart';
import 'shared.dart';

/// Settings > Android App > Category lines (lib/domain/catalog_lines.dart): the seconds a line stays, how many lines and items in a
/// line, and the category order. Saved to settings/androidHome (merged, the other Android App choices stay); the app and the website
/// use the new values from their next open.
class CatalogLinesEditor extends StatefulWidget {
  const CatalogLinesEditor({super.key, required this.store});
  final Store store;
  @override
  State<CatalogLinesEditor> createState() => _CatalogLinesEditorState();
}

class _CatalogLinesEditorState extends State<CatalogLinesEditor> {
  Store get store => widget.store;
  late final TextEditingController seconds, lines, itemsApp, itemsWeb;
  late List<String> order;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final c = CatalogLinesConfig.from(store.entries('settings'));
    seconds = TextEditingController(text: '${c.seconds}');
    lines = TextEditingController(text: '${c.lines}');
    itemsApp = TextEditingController(text: '${c.itemsApp}');
    itemsWeb = TextEditingController(text: '${c.itemsWeb}');
    final categories = [for (final e in store.entries('categories')) e.id];
    order = [...c.order.where(categories.contains), ...categories.where((id) => !c.order.contains(id))];
  }

  @override
  void dispose() {
    for (final c in [seconds, lines, itemsApp, itemsWeb]) {
      c.dispose();
    }
    super.dispose();
  }

  void _move(int i, int by) {
    final j = i + by;
    if (j < 0 || j >= order.length) return;
    setState(() => order.insert(j, order.removeAt(i)));
  }

  Future<void> _save() async {
    int? read(TextEditingController c, int min, int max) {
      final v = int.tryParse(c.text.trim());
      return v != null && v >= min && v <= max ? v : null;
    }
    final s = read(seconds, CatalogLinesConfig.minSeconds, CatalogLinesConfig.maxSeconds);
    final l = read(lines, 1, CatalogLinesConfig.maxLines);
    final a = read(itemsApp, CatalogLinesConfig.minItems, CatalogLinesConfig.maxItems);
    final w = read(itemsWeb, CatalogLinesConfig.minItems, CatalogLinesConfig.maxItems);
    if (s == null || l == null || a == null || w == null) {
      message(context, 'Line change time: 3 to 30 seconds. Lines: 1 to ${CatalogLinesConfig.maxLines}. Items in a line: ${CatalogLinesConfig.minItems} to ${CatalogLinesConfig.maxItems}.');
      return;
    }
    setState(() => busy = true);
    try {
      final fields = CatalogLinesConfig(seconds: s, lines: l, itemsApp: a, itemsWeb: w, order: order).toFields();
      await store.updateFields('settings', 'androidHome', fields, fallback: Entry('androidHome', {'name': 'Android app home', ...fields}));
      if (mounted) message(context, 'Saved. The app and the website use it from their next open.');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _number(String key, TextEditingController c, String label) => SizedBox(
    width: 240,
    child: TextField(key: ValueKey(key), controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder())),
  );

  @override
  Widget build(BuildContext context) {
    final names = {for (final e in store.entries('categories')) e.id: e.text('name')};
    return Column(
      key: const ValueKey('catalog-lines-editor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category lines', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text("Under Today's Offers, in the app and on the website: each line shows the items of one category (your Item Catalog and the photos inside the app) with the lowest price in the customer's area. After the seconds below, a whole line fades to the next category. New values apply from the next app open."),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _number('line-seconds', seconds, 'Line change time (seconds, 3 to 30)'),
          _number('line-count', lines, 'Lines on the screen'),
          _number('line-items', itemsApp, 'Items in a line (app)'),
          _number('line-items-web', itemsWeb, 'Items in a line (website)'),
        ]),
        const SizedBox(height: 12),
        const Text('Category order (1 shows first). Categories with no items are left out by themselves.'),
        for (var i = 0; i < order.length; i++)
          ListTile(
            key: ValueKey('line-category-${order[i]}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 13, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
            title: Text(names[order[i]] ?? order[i]),
            trailing: Wrap(children: [
              IconButton(key: ValueKey('line-up-${order[i]}'), tooltip: 'Move up', onPressed: i == 0 ? null : () => _move(i, -1), icon: const Icon(Icons.arrow_upward)),
              IconButton(key: ValueKey('line-down-${order[i]}'), tooltip: 'Move down', onPressed: i == order.length - 1 ? null : () => _move(i, 1), icon: const Icon(Icons.arrow_downward)),
            ]),
          ),
        const SizedBox(height: 8),
        FilledButton(key: const ValueKey('save-catalog-lines'), onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save category lines')),
      ],
    );
  }
}
