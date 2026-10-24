import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/right_boxes.dart';
import 'color_picker_field.dart';
import 'shared.dart';

/// Settings > Right Side Ad Boxes: the boxes down the right of the home page, all one size. Each box has a JPG/PNG photo, an optional
/// link (a category, shop or product) and a background colour. "Add box" / "Remove box" change how many there are (15 to start).
/// The numbers are shown only here; customers see just the photos, in this order, and a box with no photo is not shown.
class AdminRightBoxesPage extends StatefulWidget {
  const AdminRightBoxesPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminRightBoxesPage> createState() => _AdminRightBoxesPageState();
}

class _AdminRightBoxesPageState extends State<AdminRightBoxesPage> {
  Store get store => widget.store;
  bool busy = false;

  Entry get _record => rightBoxesRecord(store.entries('settings'));

  Future<void> _write(Map<String, dynamic> changes, {Set<String> remove = const {}}) async {
    setState(() => busy = true);
    try {
      final next = {..._record.data, ...changes}..removeWhere((k, _) => remove.contains(k));
      await store.updateFields('settings', rightBoxesDoc, changes, remove: remove, fallback: Entry(rightBoxesDoc, next));
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _addBox() async {
    final count = rightBoxCount(_record);
    if (count >= maxRightBoxCount) return message(context, 'The most boxes allowed is $maxRightBoxCount.');
    await _write({'count': count + 1});
  }

  Future<void> _removeBox() async {
    final count = rightBoxCount(_record);
    if (count == 0) return;
    final box = rightBoxAt(_record, count);
    if (box.imageUrl.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove Right Side Ad Box $count?'),
          content: const Text('This box has a photo. Removing the box takes it off the website.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove box')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _write({'count': count - 1}, remove: {'box${count}Image', 'box${count}Target', 'box${count}Color'});
  }

  Future<void> _upload(int n) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final name = file.name.toLowerCase();
      if (!(name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png'))) {
        if (mounted) message(context, 'Choose a JPG or PNG photo.');
        return;
      }
      setState(() => busy = true);
      final url = await store.upload(file, folder: 'ads');
      if (mounted) await _write({'box${n}Image': url});
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final record = _record;
      final count = rightBoxCount(record);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Right Side Ad Boxes', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text(
            'The boxes down the right side of the home page, top to bottom. Every box is the same size. '
            'Customers see only the photo (no number). A box with no photo shows as a light grey "ఇక్కడ మీ ప్రకటన" box of the same size.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('$count boxes', key: const ValueKey('right-box-count'), style: Theme.of(context).textTheme.titleMedium),
              FilledButton.icon(key: const ValueKey('add-right-box'), onPressed: busy ? null : _addBox, icon: const Icon(Icons.add), label: const Text('Add box')),
              OutlinedButton.icon(key: const ValueKey('remove-right-box'), onPressed: busy || count == 0 ? null : _removeBox, icon: const Icon(Icons.remove), label: const Text('Remove box')),
            ],
          ),
          const SizedBox(height: 12),
          for (var n = 1; n <= count; n++) _BoxCard(key: ValueKey('admin-right-box-$n'), number: n, box: rightBoxAt(record, n), store: store, busy: busy, onUpload: () => _upload(n), onWrite: _write),
        ],
      );
    },
  );
}

class _BoxCard extends StatelessWidget {
  const _BoxCard({super.key, required this.number, required this.box, required this.store, required this.busy, required this.onUpload, required this.onWrite});
  final int number;
  final RightBox box;
  final Store store;
  final bool busy;
  final VoidCallback onUpload;
  final Future<void> Function(Map<String, dynamic> changes, {Set<String> remove}) onWrite;

  static const _kinds = {'category': 'A category', 'shop': 'A shop', 'product': 'A product'};

  List<Entry> _items(String kind) => switch (kind) {
    'category' => store.visible('categories'),
    'shop' => store.visible('shops'),
    _ => store.visible('products'),
  };

  @override
  Widget build(BuildContext context) {
    final colon = box.target.indexOf(':');
    final kind = colon > 0 ? box.target.substring(0, colon) : '';
    final itemId = colon > 0 ? box.target.substring(colon + 1) : '';
    final items = kind.isEmpty ? const <Entry>[] : _items(kind);
    final selected = items.any((e) => e.id == itemId) ? itemId : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Right Side Ad Box $number', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                Container(
                  width: 160,
                  height: 160 * rightBoxHeight / 300,
                  decoration: BoxDecoration(
                    color: box.color.isEmpty ? Colors.white : colorFromHex(box.color, Colors.white),
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: box.imageUrl.isEmpty
                      ? const Center(child: Text('No photo\n(shows "your ad here")', textAlign: TextAlign.center))
                      : Image.network(box.imageUrl, fit: BoxFit.cover, errorBuilder: (_, error, stack) => const Center(child: Text('Photo not found'))),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(key: ValueKey('upload-right-box-$number'), onPressed: busy ? null : onUpload, icon: const Icon(Icons.upload), label: Text(box.imageUrl.isEmpty ? 'Upload JPG photo' : 'Replace photo')),
                          if (box.imageUrl.isNotEmpty)
                            TextButton(onPressed: busy ? null : () => onWrite(const {}, remove: {'box${number}Image'}), child: const Text('Remove photo')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: ValueKey('right-box-kind-$number-$kind'),
                        initialValue: kind.isEmpty ? '' : kind,
                        decoration: const InputDecoration(labelText: 'Tapping the box opens (optional)', isDense: true, border: OutlineInputBorder()),
                        items: [const DropdownMenuItem(value: '', child: Text('Nothing')), for (final e in _kinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                        onChanged: busy ? null : (v) => (v ?? '').isEmpty ? onWrite(const {}, remove: {'box${number}Target'}) : onWrite({'box${number}Target': '$v:'}),
                      ),
                      if (kind.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          key: ValueKey('right-box-item-$number-$kind-${selected ?? ''}'),
                          initialValue: selected,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: 'Which ${_kinds[kind]?.substring(2) ?? 'item'}', isDense: true, border: const OutlineInputBorder()),
                          items: [for (final e in items) DropdownMenuItem(value: e.id, child: Text(e.text('name', e.id), overflow: TextOverflow.ellipsis))],
                          onChanged: busy ? null : (v) => onWrite({'box${number}Target': '$kind:${v ?? ''}'}),
                        ),
                      ],
                      const SizedBox(height: 10),
                      ColorPickerField(label: 'Background colour', value: box.color, onChanged: (v) => v.isEmpty ? onWrite(const {}, remove: {'box${number}Color'}) : onWrite({'box${number}Color': v})),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
