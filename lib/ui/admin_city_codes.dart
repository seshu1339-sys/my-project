import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/vendor_ids.dart';
import 'shared.dart';

/// Settings > City codes: the four-letter town codes used in vendor IDs (VEN-NRPM-116-325). Changing the table changes the IDs of
/// vendors who apply from now on; an ID already given never changes.
class AdminCityCodesPage extends StatefulWidget {
  const AdminCityCodesPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminCityCodesPage> createState() => _AdminCityCodesPageState();
}

class _Row {
  _Row(CityCodeRow row) : town = TextEditingController(text: row.town), code = TextEditingController(text: row.code), pincodes = TextEditingController(text: row.pincodes);
  final TextEditingController town, code, pincodes;
  CityCodeRow get value => CityCodeRow(town.text, code.text, pincodes.text);
  void dispose() {
    town.dispose();
    code.dispose();
    pincodes.dispose();
  }
}

class _AdminCityCodesPageState extends State<AdminCityCodesPage> {
  late final List<_Row> rows = [for (final row in cityCodeRows(widget.store.entries('settings'))) _Row(row)];
  List<String> problems = const [];
  bool busy = false;

  @override
  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final values = [for (final row in rows) row.value];
    setState(() => problems = cityCodeProblems(values));
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      final data = {'name': 'City codes', 'rows': [for (final v in values) v.toJson()]};
      await widget.store.updateFields('settings', cityCodesDoc, data, fallback: Entry(cityCodesDoc, data));
      if (mounted) message(context, 'Saved. New vendor IDs use this table.');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('City codes', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text(
        'Every vendor gets an ID like VEN-NRPM-116-325: VEN, the town\'s four-letter code, the last three digits of the shop\'s pincode, '
        'and a unique number. A town that is not in this table gets the first four letters of its name. '
        'Changing the table only affects vendors who apply from now on; an ID already given never changes.',
      ),
      const SizedBox(height: 16),
      for (final (i, row) in rows.indexed)
        Card(
          key: ValueKey('city-row-$i'),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 220, child: TextField(key: ValueKey('city-town-$i'), controller: row.town, decoration: const InputDecoration(labelText: 'Town', border: OutlineInputBorder(), isDense: true))),
                SizedBox(
                  width: 130,
                  child: TextField(
                    key: ValueKey('city-code-$i'),
                    controller: row.code,
                    maxLength: 4,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Code (4 letters)', border: OutlineInputBorder(), isDense: true, counterText: ''),
                  ),
                ),
                SizedBox(width: 260, child: TextField(key: ValueKey('city-pins-$i'), controller: row.pincodes, decoration: const InputDecoration(labelText: 'Pincodes (optional)', hintText: 'e.g. 533401, 533402', border: OutlineInputBorder(), isDense: true))),
                IconButton(
                  tooltip: 'Remove this town',
                  onPressed: busy || rows.length == 1 ? null : () => setState(() => rows.removeAt(i).dispose()),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
      Wrap(
        spacing: 12,
        children: [
          OutlinedButton.icon(key: const ValueKey('city-add'), onPressed: busy ? null : () => setState(() => rows.add(_Row(const CityCodeRow('', '')))), icon: const Icon(Icons.add), label: const Text('Add town')),
          FilledButton.icon(key: const ValueKey('city-save'), onPressed: busy ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Save')),
        ],
      ),
      if (problems.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final p in problems) Text(p, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    ],
  );
}
