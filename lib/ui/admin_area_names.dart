import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/area_names.dart';
import '../domain/catalog.dart';
import 'shared.dart';

/// Settings > Area names (`settings/areaNames`, lib/domain/area_names.dart): what customers see as their area's name in the location
/// box, the greeting and "Today's ... Offers".
///   Names to fix: on the left the name the map or the post office gives ("Kancharapalem S.O"), on the right the name to show
///                 ("Kancharapalem").
///   Names not to use: a name never shown as an area ("Visakhapatnam"): the next nearer name is used instead, else the town.
/// Rows can be added at any time; a change shows for each customer the next time their place is worked out (choosing it again, or
/// the app following their GPS).
class AdminAreaNamesPage extends StatefulWidget {
  const AdminAreaNamesPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminAreaNamesPage> createState() => _AdminAreaNamesPageState();
}

class _Rename {
  _Rename(String from, String to) : from = TextEditingController(text: from), to = TextEditingController(text: to);
  final TextEditingController from, to;
  void dispose() {
    from.dispose();
    to.dispose();
  }
}

class _AdminAreaNamesPageState extends State<AdminAreaNamesPage> {
  late final Entry _saved =
      widget.store.entries('settings').where((e) => e.id == areaNamesId).firstOrNull ?? const Entry(areaNamesId, {});
  late final List<_Rename> renames = [
    for (final (from, to) in parseAreaRenames(_saved.text('renames'))) _Rename(from, to),
    if (parseAreaRenames(_saved.text('renames')).isEmpty) _Rename('', ''),
  ];
  late final List<TextEditingController> blocked = [
    for (final name in parseBlockedAreas(_saved.text('blocked'))) TextEditingController(text: name),
    if (parseBlockedAreas(_saved.text('blocked')).isEmpty) TextEditingController(),
  ];
  String? problem;
  bool busy = false;

  @override
  void dispose() {
    for (final row in renames) {
      row.dispose();
    }
    for (final c in blocked) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final half = renames.any((r) => r.from.text.trim().isEmpty != r.to.text.trim().isEmpty);
    setState(() => problem = half ? 'Fill in both sides of every name to fix, or clear the row.' : null);
    if (half) return;
    setState(() => busy = true);
    try {
      final data = {
        'name': 'Area names',
        'renames': areaRenamesText([for (final r in renames) (r.from.text, r.to.text)]),
        'blocked': [for (final c in blocked) if (c.text.trim().isNotEmpty) c.text.trim()].join('\n'),
      };
      await widget.store.updateFields('settings', areaNamesId, data, fallback: Entry(areaNamesId, data));
      if (mounted) message(context, 'Saved. Customers see these names the next time their place is set.');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration _box(String label, {String? hint}) =>
      InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true);

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Area names', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text(
        'Customers see the name of their area (for example Kancharapalem or Gurudwara) in the location box, the greeting and '
        '"Today\'s ... Offers". It comes from the map and the post office list. Here you can fix a name, or stop a name from being '
        'used: then the next nearer area name is shown, else the town.',
      ),
      const SizedBox(height: 20),
      Text('Names to fix', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final (i, row) in renames.indexed)
        Card(
          key: ValueKey('area-rename-$i'),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(key: ValueKey('area-from-$i'), controller: row.from, decoration: _box('Name on the map', hint: 'Kancharapalem S.O')),
                ),
                const Icon(Icons.arrow_forward),
                SizedBox(
                  width: 260,
                  child: TextField(key: ValueKey('area-to-$i'), controller: row.to, decoration: _box('Name to show', hint: 'Kancharapalem')),
                ),
                IconButton(
                  tooltip: 'Remove this row',
                  onPressed: busy ? null : () => setState(() => renames.removeAt(i).dispose()),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('area-add-rename'),
          onPressed: busy ? null : () => setState(() => renames.add(_Rename('', ''))),
          icon: const Icon(Icons.add),
          label: const Text('Add a name to fix'),
        ),
      ),
      const SizedBox(height: 24),
      Text('Names not to use', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text('For example a big city\'s name: a nearer area name is shown instead.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      for (final (i, c) in blocked.indexed)
        Padding(
          key: ValueKey('area-blocked-row-$i'),
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: TextField(key: ValueKey('area-blocked-$i'), controller: c, decoration: _box('Name', hint: 'Visakhapatnam')),
                ),
              ),
              IconButton(
                tooltip: 'Remove this name',
                onPressed: busy ? null : () => setState(() => blocked.removeAt(i).dispose()),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('area-add-blocked'),
          onPressed: busy ? null : () => setState(() => blocked.add(TextEditingController())),
          icon: const Icon(Icons.add),
          label: const Text('Add a name not to use'),
        ),
      ),
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const ValueKey('area-save'),
          onPressed: busy ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ),
      if (problem != null) ...[
        const SizedBox(height: 12),
        Text(problem!, key: const ValueKey('area-problem'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    ],
  );
}
