import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/android_sizes.dart';
import '../domain/catalog.dart';
import 'android_layout.dart';
import 'shared.dart';

/// The Sizes block of Settings > Android App: every size of the Android home screen, apart from the website's. Saved to
/// settings/androidSizes, which only the app reads, and shown in the app at once. The website keeps its own sizes in Settings > Layout.
class AndroidSizesEditor extends StatefulWidget {
  const AndroidSizesEditor({super.key, required this.store});
  final Store store;
  @override
  State<AndroidSizesEditor> createState() => _AndroidSizesEditorState();
}

class _AndroidSizesEditorState extends State<AndroidSizesEditor> {
  Store get store => widget.store;
  final fields = <String, TextEditingController>{};
  bool busy = false;

  Entry get _record => store.entries('settings').where((e) => e.id == androidSizesId).firstOrNull ?? const Entry(androidSizesId, {});

  String _show(double? v) => v == null ? '' : (v == v.roundToDouble() ? '${v.round()}' : '$v');

  void _load() {
    final sizes = AndroidSizes.from(store.entries('settings'));
    for (final part in androidSizeParts) {
      for (final field in part.fields) {
        final k = AndroidSizes.key(part.id, field.id);
        (fields[k] ??= TextEditingController()).text = _show(sizes.value(part.id, field.id));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work, String done) async {
    setState(() => busy = true);
    try {
      await work();
      if (mounted) {
        setState(_load);
        message(context, done);
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    final out = <String, dynamic>{};
    for (final part in androidSizeParts) {
      for (final field in part.fields) {
        final k = AndroidSizes.key(part.id, field.id);
        final text = fields[k]!.text.trim();
        if (text.isEmpty) continue;
        final v = double.tryParse(text);
        if (v == null) {
          message(context, '${part.title}: ${field.label} must be a number.');
          return;
        }
        out[k] = v.clamp(field.min, field.max).toDouble();
      }
    }
    await _run(
      () => store.save('settings', Entry(androidSizesId, {'name': 'Android app sizes', if (_record.text('separate') == 'true') 'separate': 'true', ...out})),
      'Saved. The Android app shows it at once; the website is not changed.',
    );
  }

  Future<void> _copy() async {
    if (AndroidSizes.from(store.entries('settings')).values.isNotEmpty) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Copy website sizes to Android?'),
          content: const Text('The sizes already saved for the Android app will be replaced.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(key: const ValueKey('android-sizes-copy-yes'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Replace')),
          ],
        ),
      );
      if (sure != true) return;
    }
    await _run(
      () => store.save('settings', Entry(androidSizesId, AndroidSizes.copiedFields(tightForAndroid(store.entries('settings'))))),
      'Copied. The app looks the same, and from now on the website and the Android app have separate sizes.',
    );
  }

  Widget _field(AndroidSizePart part, AndroidSizeField field, bool separate) {
    final website = part.recordId.isEmpty ? null : AndroidSizes.websiteValue(store.entries('settings'), part, field);
    return SizedBox(
      width: 230,
      child: TextField(
        key: ValueKey('android-size-${part.id}-${field.id}'),
        controller: fields[AndroidSizes.key(part.id, field.id)],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: field.label,
          helperText: separate || part.recordId.isEmpty ? 'Blank = normal size' : 'Blank = website (${website == null ? 'normal size' : _show(website)})',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final separate = _record.text('separate') == 'true';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sizes in the Android app', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          separate
              ? 'The website and the Android app have separate sizes. Changing one never changes the other.'
              : 'A blank size follows the website. Use the button below once to separate them completely; the app keeps its look.',
          key: const ValueKey('android-sizes-state'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(key: const ValueKey('android-sizes-copy'), onPressed: busy ? null : _copy, icon: const Icon(Icons.content_copy), label: const Text('Copy website sizes to Android')),
        const SizedBox(height: 8),
        for (final part in androidSizeParts)
          ExpansionTile(
            key: ValueKey('android-size-part-${part.id}'),
            title: Text(part.title),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            expandedAlignment: Alignment.centerLeft,
            maintainState: true,
            children: [
              Wrap(spacing: 12, runSpacing: 12, children: [for (final field in part.fields) _field(part, field, separate)]),
            ],
          ),
        const SizedBox(height: 12),
        FilledButton(key: const ValueKey('save-android-sizes'), onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save sizes')),
      ],
    );
  }
}
