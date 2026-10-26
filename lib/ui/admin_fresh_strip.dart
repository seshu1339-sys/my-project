import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/fresh_strip.dart';
import '../domain/item_shops.dart';
import 'shared.dart';

/// Settings > Fresh Fruits & Vegetables: the items of the home page strip under Today's Offers, in order (settings/freshStrip,
/// lib/domain/fresh_strip.dart). Typing an item's name finds the items the shops already sell, each with its photo; choosing one
/// adds it at the end. Each item has its number; move it up or down, or take it out. The home page shows them in this order, 9 at a
/// time. With no items here, the strip shows the vegetables and fruits as before.
class AdminFreshStripPage extends StatefulWidget {
  const AdminFreshStripPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminFreshStripPage> createState() => _AdminFreshStripPageState();
}

class _AdminFreshStripPageState extends State<AdminFreshStripPage> {
  final search = TextEditingController();
  Store get store => widget.store;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<ItemPick> get _items => freshStripItems(store.entries('settings').where((e) => e.id == freshStripRecord).firstOrNull);

  Future<void> _save(List<ItemPick> items) async {
    final data = {'items': [for (final i in items) i.toMap()]};
    try {
      await store.updateFields('settings', freshStripRecord, data, fallback: Entry(freshStripRecord, data));
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  void _add(ItemPick pick) {
    final items = _items;
    search.clear();
    setState(() {});
    if (items.any((i) => i.key == pick.key)) return message(context, '${pick.name} is already in the list.');
    _save([...items, pick]);
  }

  void _move(int from, int to) {
    final items = _items;
    if (to < 0 || to >= items.length) return;
    final item = items.removeAt(from);
    items.insert(to, item);
    _save(items);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final items = _items;
      final picks = itemPicks(store.entries('products'), search.text);
      return ListView(
        key: const ValueKey('admin-fresh-strip'),
        padding: const EdgeInsets.all(16),
        children: [
          Text('Fresh Fruits & Vegetables', style: Theme.of(context).textTheme.headlineSmall),
          const Text(
            'The home page shows these items in this order, 9 at a time, then the next 9, and round again. Each item shows the lowest '
            'price in the customer\'s town; an item no shop there sells is left out. With no items here, the strip shows the vegetables '
            'and fruits as before.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('fresh-search'),
            controller: search,
            decoration: const InputDecoration(labelText: 'Add an item: type its name', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              final found = itemPicks(store.entries('products'), search.text);
              if (found.isNotEmpty) _add(found.first);
            },
          ),
          for (final pick in picks)
            ListTile(
              key: ValueKey('fresh-pick-${pick.key}'),
              leading: ClipOval(child: SizedBox(width: 40, height: 40, child: ProductArt(Entry('pick', {'imageUrl': pick.imageUrl}), height: 40, width: 40))),
              title: Text(pick.name),
              trailing: items.any((i) => i.key == pick.key) ? const Text('Added') : const Icon(Icons.add_circle_outline),
              onTap: () => _add(pick),
            ),
          const SizedBox(height: 16),
          Text('In the strip (${items.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (items.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No items chosen yet: the strip shows the vegetables and fruits.')),
          for (final (i, item) in items.indexed)
            Card(
              key: ValueKey('fresh-item-${item.key}'),
              child: ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                    const SizedBox(width: 8),
                    ClipOval(child: SizedBox(width: 40, height: 40, child: ProductArt(Entry('item', {'imageUrl': item.imageUrl}), height: 40, width: 40))),
                  ],
                ),
                title: Text(item.name),
                subtitle: i % freshStripPageSize == 0 ? Text('Group ${i ~/ freshStripPageSize + 1} starts here') : null,
                trailing: Wrap(
                  children: [
                    IconButton(tooltip: 'Up', key: ValueKey('fresh-up-${item.key}'), onPressed: i == 0 ? null : () => _move(i, i - 1), icon: const Icon(Icons.arrow_upward)),
                    IconButton(tooltip: 'Down', key: ValueKey('fresh-down-${item.key}'), onPressed: i == items.length - 1 ? null : () => _move(i, i + 1), icon: const Icon(Icons.arrow_downward)),
                    IconButton(
                      tooltip: 'Take out',
                      key: ValueKey('fresh-remove-${item.key}'),
                      onPressed: () => _save([...items]..removeAt(i)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
