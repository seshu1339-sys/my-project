import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/quick_items.dart';
import 'quick_add_core.dart';
import 'quick_add_photo.dart';

class _BatchRow {
  final name = TextEditingController();
  final rate = TextEditingController();
  String? unit;
  Uint8List? photo;
  String? submissionId;
  bool picking = false;
  void dispose() {
    name.dispose();
    rate.dispose();
  }
}

/// Vendor: up to 5 items with photos at once, in one category, with one start and duration. The
/// phone's GPS is checked once: the vendor must be within 100 m of the shop.
class QuickBatchFormPage extends StatefulWidget {
  const QuickBatchFormPage({super.key, required this.store, required this.account, required this.category, this.env = const QuickEnv()});
  final Store store;
  final Entry account;
  final Entry category;
  final QuickEnv env;
  @override
  State<QuickBatchFormPage> createState() => _QuickBatchFormPageState();
}

class _QuickBatchFormPageState extends State<QuickBatchFormPage> {
  final rows = <_BatchRow>[_BatchRow()];
  final timing = QuickTiming();
  List<String> errors = const [];
  bool busy = false;

  @override
  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
    super.dispose();
  }

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  Future<void> _pick(_BatchRow row, ImageSource source) async {
    setState(() => row.picking = true);
    try {
      final result = await (widget.env.pick ?? (s) => quickDefaultPick(widget.store, s))(source);
      if (result != null && mounted) {
        setState(() {
          row.photo = result.bytes;
          row.submissionId = result.submissionId;
          errors = const [];
        });
      }
    } catch (e) {
      if (mounted) toast(quickCleanError(e));
    } finally {
      if (mounted) setState(() => row.picking = false);
    }
  }

  List<String> _errors() {
    final out = <String>[];
    for (final (i, row) in rows.indexed) {
      for (final problem in quickItemErrors(
        name: row.name.text,
        rate: row.rate.text,
        unit: row.unit,
        hasPhoto: row.photo != null,
        needsLocation: false,
        locationId: null,
        timing: QuickTiming(),
      )) {
        out.add('Item ${i + 1}: $problem');
      }
    }
    return [...out, ...quickTimingErrors(timing, null)];
  }

  Future<void> save() async {
    final problems = _errors();
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      final fix = await widget.env.fix();
      final metres = quickMetresFromShop(widget.account, fix);
      if (metres == null || metres > quickShopRadiusMetres) {
        if (mounted) setState(() => errors = [quickNotAtShop]);
        return;
      }
      await widget.env.run(widget.store, 'saveQuickItems', {
        'categoryId': widget.category.id,
        'items': [
          for (final row in rows)
            {
              'submissionId': row.submissionId,
              'name': row.name.text.trim(),
              'price': double.parse(row.rate.text.trim()),
              'unit': row.unit,
            },
        ],
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        ...timing.toPayload(),
      });
      if (!mounted) return;
      setState(() => busy = false);
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Saved'),
          content: Text('${rows.length} ${rows.length == 1 ? 'item was' : 'items were'} sent to the admin. They go live after the admin approves them.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialog);
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: const Text('Done'),
            ),
            FilledButton(
              key: const ValueKey('quick-add-next'),
              onPressed: () {
                Navigator.pop(dialog);
                Navigator.pop(context);
              },
              child: const Text('Add more items'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        final message = quickCleanError(e);
        setState(() => errors = [message]);
        toast(message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.category.text('name', 'Add items'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          key: const ValueKey('quick-location-fixed'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: Text('${widget.account.text('locationTown')}, ${widget.account.text('locationDistrict')}'),
          subtitle: const Text('Your shop. You must be within 100 m of it to save.'),
        ),
        for (final (i, row) in rows.indexed)
          Card(
            key: ValueKey('quick-row-$i'),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(child: Text('Item ${i + 1}', style: Theme.of(context).textTheme.titleMedium)),
                    if (rows.length > 1)
                      IconButton(
                        key: ValueKey('quick-row-remove-$i'),
                        tooltip: 'Remove this item',
                        onPressed: () => setState(() => rows.removeAt(i).dispose()),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ]),
                  QuickPhotoArea(bytes: row.photo, busy: row.picking, height: 140, suffix: '-$i', onPick: (s) => _pick(row, s)),
                  const SizedBox(height: 12),
                  TextField(
                    key: ValueKey('quick-name-$i'),
                    controller: row.name,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(labelText: 'Item name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        key: ValueKey('quick-rate-$i'),
                        controller: row.rate,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(labelText: 'Rate (₹)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('quick-unit-$i'),
                        initialValue: row.unit,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                        items: [for (final u in quickUnits) DropdownMenuItem(value: u, child: Text(u))],
                        onChanged: (v) => setState(() => row.unit = v),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        if (rows.length < quickMaxBatch)
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              key: const ValueKey('quick-row-add'),
              onPressed: () => setState(() => rows.add(_BatchRow())),
              icon: const Icon(Icons.add),
              label: Text('Add another item (${rows.length}/$quickMaxBatch)'),
            ),
          ),
        const SizedBox(height: 16),
        QuickTimingFields(timing: timing),
        const SizedBox(height: 16),
        if (errors.isNotEmpty)
          Card(
            key: const ValueKey('quick-error'),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final e in errors) Text(e.startsWith('మీరు') ? e : '• $e')],
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: FilledButton(
            key: const ValueKey('quick-save'),
            onPressed: busy ? null : save,
            child: busy ? const CircularProgressIndicator() : Text('Save ${rows.length} ${rows.length == 1 ? 'item' : 'items'}', style: const TextStyle(fontSize: 22)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}
