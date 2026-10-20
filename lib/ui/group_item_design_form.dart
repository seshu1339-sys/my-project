import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'color_picker_field.dart';
import 'layout_settings.dart';
import 'shared.dart';

const _fontWeightOptions = <String, String>{
  '400': 'Normal',
  '500': 'Medium',
  '600': 'Semi-bold',
  '700': 'Bold',
  '800': 'Extra bold',
};

/// The "design options for one item" screen a repeating group's sub-number
/// opens -- color, replace-image, brightness and text style for exactly
/// ONE item (one ad, one category, one carousel slide...), and nothing
/// else. Deliberately has NO width/height/size field at all: size lives
/// only on the group's own main number (see element_groups.dart's doc
/// comment), so every item in a group is always the same size.
///
/// Reads and writes [collection]/[id] directly -- a real Firestore
/// document shared with that item's own full content editor (name,
/// image... schedule for a promotion, etc.), so this form and that editor
/// can never disagree about what's currently saved; this one just never
/// shows the content fields, matching "changing design must never change
/// content" from the admin's own rule.
class GroupItemDesignForm extends StatefulWidget {
  const GroupItemDesignForm({
    super.key,
    required this.store,
    required this.collection,
    required this.id,
    this.onSaved,
  });
  final Store store;
  final String collection;
  final String id;
  final VoidCallback? onSaved;
  @override
  State<GroupItemDesignForm> createState() => GroupItemDesignFormState();
}

class GroupItemDesignFormState extends State<GroupItemDesignForm> {
  Map<String, TextEditingController> controllers = {};
  Map<String, dynamic> values = {};
  bool busy = false;
  Timer? _debounce;
  Entry get saved =>
      widget.store
          .entries(widget.collection)
          .where((e) => e.id == widget.id)
          .firstOrNull ??
      Entry(widget.id, const {});

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GroupItemDesignForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection != widget.collection || oldWidget.id != widget.id)
      _load();
  }

  void _load() {
    for (final c in controllers.values) {
      c.dispose();
    }
    controllers = {
      'imageUrl': TextEditingController(text: saved.text('imageUrl')),
      'backgroundColor': TextEditingController(
        text: saved.text('backgroundColor'),
      ),
      'textColor': TextEditingController(text: saved.text('textColor')),
      'borderColor': TextEditingController(text: saved.text('borderColor')),
      'brightness': TextEditingController(text: saved.text('brightness')),
    };
    values = {
      'active': saved.active,
      'fontFamily': saved.text('fontFamily'),
      'fontStyle': saved.text('fontStyle'),
      'fontWeight': saved.text('fontWeight'),
    };
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), save);
  }

  void _setValue(String key, dynamic value) {
    setState(() => values[key] = value);
    _scheduleSave();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final data = {...saved.data, 'active': values['active']};
      for (final entry in controllers.entries) {
        final text = entry.value.text.trim();
        if (text.isEmpty) {
          data.remove(entry.key);
        } else if (entry.key == 'brightness') {
          data[entry.key] = double.tryParse(text) ?? 1.0;
        } else {
          data[entry.key] = text;
        }
      }
      for (final key in ['fontFamily', 'fontStyle', 'fontWeight']) {
        final value = (values[key] as String?) ?? '';
        if (value.isEmpty) {
          data.remove(key);
        } else {
          data[key] = value;
        }
      }
      await widget.store.save(widget.collection, Entry(widget.id, data));
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _uploadImage() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      setState(() => busy = true);
      final url = await widget.store.upload(file);
      if (mounted) {
        setState(() => controllers['imageUrl']!.text = url);
        _scheduleSave();
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columnWidth = c.maxWidth >= 800
          ? (c.maxWidth - 32) / 3
          : c.maxWidth >= 550
          ? (c.maxWidth - 16) / 2
          : c.maxWidth;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          SizedBox(
            width: columnWidth,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Visible on the site'),
              value: values['active'] as bool,
              onChanged: (v) => _setValue('active', v),
            ),
          ),
          SizedBox(
            width: columnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: controllers['imageUrl'],
                  decoration: const InputDecoration(
                    labelText: 'Image URL (optional — or use Upload below)',
                  ),
                  onChanged: (_) => _scheduleSave(),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : _uploadImage,
                      icon: const Icon(Icons.upload, size: 18),
                      label: const Text('Upload image'),
                    ),
                    if (controllers['imageUrl']!.text.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () {
                                setState(
                                  () => controllers['imageUrl']!.clear(),
                                );
                                _scheduleSave();
                              },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove image'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: columnWidth,
            child: ColorPickerField(
              label: 'Background color',
              value: controllers['backgroundColor']!.text,
              onChanged: (v) {
                setState(() => controllers['backgroundColor']!.text = v);
                _scheduleSave();
              },
            ),
          ),
          SizedBox(
            width: columnWidth,
            child: ColorPickerField(
              label: 'Text color',
              value: controllers['textColor']!.text,
              onChanged: (v) {
                setState(() => controllers['textColor']!.text = v);
                _scheduleSave();
              },
            ),
          ),
          SizedBox(
            width: columnWidth,
            child: ColorPickerField(
              label: 'Border color',
              value: controllers['borderColor']!.text,
              onChanged: (v) {
                setState(() => controllers['borderColor']!.text = v);
                _scheduleSave();
              },
            ),
          ),
          SizedBox(
            width: columnWidth,
            child: TextFormField(
              controller: controllers['brightness'],
              decoration: const InputDecoration(
                labelText: 'Brightness (0.2 - 2, optional)',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => _scheduleSave(),
            ),
          ),
          SizedBox(
            width: columnWidth,
            child: DropdownButtonFormField<String>(
              initialValue: (values['fontFamily'] as String).isEmpty
                  ? null
                  : values['fontFamily'] as String,
              decoration: const InputDecoration(labelText: 'Font family'),
              hint: const Text('Theme default'),
              items: [
                for (final f in fontFamilyOptions)
                  DropdownMenuItem(value: f, child: Text(f)),
              ],
              onChanged: (v) => _setValue('fontFamily', v ?? ''),
            ),
          ),
          SizedBox(
            width: columnWidth,
            child: DropdownButtonFormField<String>(
              initialValue: (values['fontStyle'] as String).isEmpty
                  ? 'normal'
                  : values['fontStyle'] as String,
              decoration: const InputDecoration(labelText: 'Font style'),
              items: const [
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'italic', child: Text('Italic')),
              ],
              onChanged: (v) => _setValue('fontStyle', v ?? 'normal'),
            ),
          ),
          SizedBox(
            width: columnWidth,
            child: DropdownButtonFormField<String>(
              initialValue: _fontWeightOptions.containsKey(values['fontWeight'])
                  ? values['fontWeight'] as String
                  : null,
              decoration: const InputDecoration(labelText: 'Font weight'),
              hint: const Text('Theme default'),
              items: [
                for (final e in _fontWeightOptions.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => _setValue('fontWeight', v ?? ''),
            ),
          ),
        ],
      );
    },
  );
}
