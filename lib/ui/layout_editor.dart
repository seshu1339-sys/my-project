import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'color_picker_field.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'home_section_config.dart';
import 'page_elements.dart';
import 'shared.dart';

class LayoutSettingsPage extends StatefulWidget {
  const LayoutSettingsPage({super.key, required this.store});
  final Store store;
  @override
  State<LayoutSettingsPage> createState() => _LayoutSettingsPageState();
}

class _LayoutSettingsPageState extends State<LayoutSettingsPage> {
  final formKey = GlobalKey<LayoutFieldsFormState>();
  String component = 'search';

  @override
  Widget build(BuildContext context) {
    if (widget.store.live && !widget.store.admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Layout settings')),
        body: const Center(child: Text('Administrator access required.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('UI Customization / Layout Settings')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => formKey.currentState?.save(),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save layout'),
              ),
              OutlinedButton(
                onPressed: () => formKey.currentState?.save(reset: true),
                child: const Text('Reset this component to default'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Each component has independent settings. Blank values use responsive defaults. '
            'Dimensions are limited to the available screen; content can grow to remain readable. '
            'Global fonts and colors are in Theme Settings. Individual ad content and schedules are in Promotions.',
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            key: ValueKey(component),
            initialValue: component,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Component'),
            items: [
              for (final item in layoutComponents.entries)
                DropdownMenuItem(value: item.key, child: Text(numberedLabel(item.key, item.value))),
            ],
            onChanged: (value) async {
              if (value == null || value == component) return;
              if (formKey.currentState?.dirty == true &&
                  !await (formKey.currentState!.save())) {
                return;
              }
              if (mounted) setState(() => component = value);
            },
          ),
          const SizedBox(height: 16),
          LayoutFieldsForm(key: formKey, store: widget.store, component: component),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// How one field's value is edited — picked once per key by _kindOf below,
// not per component, so every component's form stays consistent.
enum _FieldKind { toggle, color, fontFamily, fontStyle, fontWeight, animation, alignment, direction, number, text }

const _toggleLabels = {'visible': 'Visible on the site', 'scrollEnabled': 'Scroll enabled'};

_FieldKind _kindOf(String key) {
  if (_toggleLabels.containsKey(key)) return _FieldKind.toggle;
  if (key.endsWith('Color') || key == 'gradientStart' || key == 'gradientEnd') return _FieldKind.color;
  if (key == 'fontFamily') return _FieldKind.fontFamily;
  if (key == 'fontStyle') return _FieldKind.fontStyle;
  if (key == 'fontWeight') return _FieldKind.fontWeight;
  if (key == 'animation') return _FieldKind.animation;
  if (key == 'alignment') return _FieldKind.alignment;
  if (key == 'direction') return _FieldKind.direction;
  if (dimensionFields.containsKey(key)) return _FieldKind.number;
  return _FieldKind.text;
}

/// The field-editing body for one layout component: one typed control per
/// key from `allFieldsFor` (layout_settings.dart) — a toggle, color picker,
/// dropdown, segmented buttons, or a px-suffixed number field, picked by
/// `_kindOf` above — validates, and saves/resets to `settings/section_<component>`.
/// Split out of `LayoutSettingsPage` so the admin Visual Editor can mount it
/// inline, directly beside the live preview, without the dropdown/page chrome.
class LayoutFieldsForm extends StatefulWidget {
  const LayoutFieldsForm({
    super.key,
    required this.store,
    required this.component,
    this.onSaved,
    this.autoSave = false,
  });
  final Store store;
  final String component;
  final VoidCallback? onSaved;
  // When true (the admin Visual Editor's live-preview panel), every field
  // edit debounces into a real save a moment after the admin stops
  // changing it, instead of waiting for an explicit "Save layout" tap — so
  // the preview reflects changes "instantly" using the exact same,
  // already-validated save() path, not a second persistence mechanism.
  // LayoutSettingsPage (the plain full-page form) leaves this false/unchanged.
  final bool autoSave;
  @override
  State<LayoutFieldsForm> createState() => LayoutFieldsFormState();
}

class LayoutFieldsFormState extends State<LayoutFieldsForm> {
  final form = GlobalKey<FormState>();
  // Number/free-text fields are still backed by a TextEditingController
  // (they need real typing + a blinking cursor); every other kind
  // (toggle/color/dropdown/segmented) keeps its current value directly here.
  Map<String, TextEditingController> controllers = {};
  Map<String, dynamic> values = {};
  bool busy = false;
  bool dirty = false;
  Timer? _debounce;
  int _animationPreviewTick = 0;
  Entry get saved => sectionConfig(widget.store.entries('settings'), widget.component);
  List<String> get fields => allFieldsFor(widget.component);

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant LayoutFieldsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.component != widget.component) load();
  }

  void load() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    controllers = {};
    values = {};
    for (final key in fields) {
      switch (_kindOf(key)) {
        case _FieldKind.toggle:
          // 'visible' defaults to true when unset (sectionVisible's own
          // rule); 'scrollEnabled' defaults to false (see
          // home_scheduled_promo.dart's own default — flipped from true
          // after the ad/box overlap fix). Entry.text() normalizes a
          // legacy string 'true'/'false' the same as a real stored bool.
          values[key] = key == 'visible' ? sectionVisible(saved) : saved.text(key, 'false') == 'true';
        case _FieldKind.color:
        case _FieldKind.fontFamily:
        case _FieldKind.fontStyle:
        case _FieldKind.fontWeight:
        case _FieldKind.animation:
        case _FieldKind.alignment:
        case _FieldKind.direction:
          values[key] = saved.text(key);
        case _FieldKind.number:
        case _FieldKind.text:
          controllers[key] = TextEditingController(text: saved.text(key));
      }
    }
    dirty = false;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onFieldChanged() {
    dirty = true;
    if (!widget.autoSave) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted && form.currentState?.validate() == true) save();
    });
  }

  void _setValue(String key, dynamic value) {
    setState(() => values[key] = value);
    _onFieldChanged();
  }

  Map<String, dynamic> _collectValues() {
    final out = <String, dynamic>{...saved.data};
    for (final entry in controllers.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) {
        out.remove(entry.key);
      } else {
        out[entry.key] = dimensionFields.containsKey(entry.key) ? (double.tryParse(text) ?? 0) : text;
      }
    }
    for (final entry in values.entries) {
      final value = entry.value;
      if (value is bool) {
        out[entry.key] = value;
      } else if (value is String && value.trim().isEmpty) {
        out.remove(entry.key);
      } else {
        out[entry.key] = value;
      }
    }
    return out;
  }

  Future<bool> save({bool reset = false}) async {
    if (!reset && !form.currentState!.validate()) return false;
    setState(() => busy = true);
    try {
      final data = _collectValues();
      for (final axis in ['Width', 'Height']) {
        final min = (data['min$axis'] as num?) ?? 0;
        final max = (data['max$axis'] as num?) ?? 0;
        if (!reset && max > 0 && min > max) {
          throw StateError('Minimum $axis must not exceed maximum $axis.');
        }
      }
      if (reset) {
        final preserved = Map<String, dynamic>.from(saved.data);
        for (final key in fields) {
          preserved.remove(key);
        }
        await widget.store.save(
          'settings',
          Entry('section_${widget.component}', preserved),
        );
      } else {
        await widget.store.save(
          'settings',
          Entry('section_${widget.component}', {...data, 'section': widget.component}),
        );
      }
      if (mounted) {
        dirty = false;
        if (reset) load();
        message(
          context,
          reset ? 'Layout dimensions reset to defaults' : 'Layout saved',
        );
        widget.onSaved?.call();
      }
      return true;
    } catch (e) {
      if (mounted) message(context, e);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? _numberValidator(String key, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final rule = dimensionFields[key]!;
    final number = double.tryParse(text);
    if (number == null || !number.isFinite || number < rule.$2 || number > rule.$3) {
      return 'Use ${rule.$2} to ${rule.$3}';
    }
    if ({
          'columns', 'visibleCount', 'rows', 'mobileColumns', 'tabletColumns',
          'desktopColumns', 'mobileRows', 'tabletRows', 'desktopRows',
        }.contains(key) &&
        number != number.round()) {
      return 'Use a whole number';
    }
    return null;
  }

  Widget _fieldWidget(String key) {
    switch (_kindOf(key)) {
      case _FieldKind.toggle:
        return SwitchListTile.adaptive(
          key: ValueKey('${widget.component}-$key'),
          contentPadding: EdgeInsets.zero,
          title: Text(_toggleLabels[key]!),
          value: values[key] as bool,
          onChanged: (v) => _setValue(key, v),
        );
      case _FieldKind.color:
        final isIconOnly = {
          'notificationIcon', 'wishlistIcon', 'cartIcon', 'menuIcon',
        }.contains(widget.component);
        return ColorPickerField(
          key: ValueKey('${widget.component}-$key'),
          label: key == 'textColor' && isIconOnly
              ? 'Icon color'
              : const {
                  'backgroundColor': 'Background color',
                  'textColor': 'Text color',
                  'borderColor': 'Border color',
                  'gradientStart': 'Gradient start',
                  'gradientEnd': 'Gradient end',
                }[key]!,
          value: values[key] as String,
          onChanged: (v) => _setValue(key, v),
        );
      case _FieldKind.fontFamily:
        return DropdownButtonFormField<String>(
          key: ValueKey('${widget.component}-$key'),
          initialValue: (values[key] as String).isEmpty ? null : values[key] as String,
          decoration: const InputDecoration(labelText: 'Font family'),
          hint: const Text('Theme default'),
          items: [for (final f in fontFamilyOptions) DropdownMenuItem(value: f, child: Text(f))],
          onChanged: (v) => _setValue(key, v ?? ''),
        );
      case _FieldKind.fontStyle:
        return DropdownButtonFormField<String>(
          key: ValueKey('${widget.component}-$key'),
          initialValue: (values[key] as String).isEmpty ? 'normal' : values[key] as String,
          decoration: const InputDecoration(labelText: 'Font style'),
          items: const [
            DropdownMenuItem(value: 'normal', child: Text('Normal')),
            DropdownMenuItem(value: 'italic', child: Text('Italic')),
          ],
          onChanged: (v) => _setValue(key, v ?? 'normal'),
        );
      case _FieldKind.fontWeight:
        return DropdownButtonFormField<String>(
          key: ValueKey('${widget.component}-$key'),
          initialValue: (values[key] as String).isEmpty ? null : values[key] as String,
          decoration: const InputDecoration(labelText: 'Font weight'),
          hint: const Text('Default'),
          items: const [
            DropdownMenuItem(value: '400', child: Text('Normal')),
            DropdownMenuItem(value: '500', child: Text('Medium')),
            DropdownMenuItem(value: '600', child: Text('Semi-bold')),
            DropdownMenuItem(value: '700', child: Text('Bold')),
            DropdownMenuItem(value: '800', child: Text('Extra bold')),
          ],
          onChanged: (v) => _setValue(key, v ?? ''),
        );
      case _FieldKind.direction:
        final isNotice = widget.component == 'notice';
        return DropdownButtonFormField<String>(
          key: ValueKey('${widget.component}-$key'),
          initialValue: (values[key] as String).isEmpty ? (isNotice ? 'rtl' : 'up') : values[key] as String,
          decoration: InputDecoration(labelText: isNotice ? 'Direction' : 'Scroll direction'),
          items: isNotice
              ? const [
                  DropdownMenuItem(value: 'rtl', child: Text('Right to left')),
                  DropdownMenuItem(value: 'ltr', child: Text('Left to right')),
                ]
              : const [
                  DropdownMenuItem(value: 'up', child: Text('Up')),
                  DropdownMenuItem(value: 'down', child: Text('Down')),
                ],
          onChanged: (v) => _setValue(key, v ?? ''),
        );
      case _FieldKind.animation:
        // A Column, not a Row, for the dropdown + Preview controls — this
        // field sits inside a Wrap whose own item width can be as narrow as
        // a phone screen (see build() below); packing dropdown+button+demo
        // swatch into one fixed Row overflowed there. Wrap (not Row) for the
        // second line too, so the button and demo swatch can drop to their
        // own line rather than overflow if that width is ever even tighter.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('${widget.component}-$key'),
              initialValue: (values[key] as String).isEmpty ? 'none' : values[key] as String,
              decoration: const InputDecoration(labelText: 'Entrance animation'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('None')),
                DropdownMenuItem(value: 'fade', child: Text('Fade in')),
                DropdownMenuItem(value: 'slide', child: Text('Slide + fade in')),
              ],
              onChanged: (v) => _setValue(key, v ?? 'none'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _animationPreviewTick++),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Preview'),
                ),
                KeyedSubtree(
                  key: ValueKey('anim-preview-${widget.component}-$_animationPreviewTick'),
                  child: applyEntranceAnimation(
                    Entry('preview', {'animation': values[key]}),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: AppTokens.primary, borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case _FieldKind.alignment:
        final current = (values[key] as String).isEmpty ? 'start' : values[key] as String;
        return InputDecorator(
          decoration: const InputDecoration(labelText: 'Alignment', border: InputBorder.none),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'start', icon: Icon(Icons.format_align_left), label: Text('Left')),
              ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center), label: Text('Center')),
              ButtonSegment(value: 'end', icon: Icon(Icons.format_align_right), label: Text('Right')),
            ],
            selected: {current},
            onSelectionChanged: (s) => _setValue(key, s.first),
          ),
        );
      case _FieldKind.number:
      case _FieldKind.text:
        final isPixel = pixelFields.contains(key);
        return TextFormField(
          key: ValueKey('${widget.component}-$key'),
          controller: controllers[key],
          decoration: InputDecoration(
            labelText: dimensionFields[key]?.$1 ??
                {
                  'fontFamily': 'Font family',
                  'iconUrl': 'Icon image URL (optional)',
                  'text': 'Text content (optional — leave blank for the default)',
                }[key],
            suffixText: isPixel ? 'px' : null,
            helperText: dimensionFields.containsKey(key)
                ? '${dimensionFields[key]!.$2} – ${dimensionFields[key]!.$3}'
                : null,
          ),
          keyboardType: dimensionFields.containsKey(key)
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          onChanged: (_) => _onFieldChanged(),
          validator: dimensionFields.containsKey(key) ? (v) => _numberValidator(key, v) : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: LayoutBuilder(
      builder: (context, c) => Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          for (final key in fields)
            SizedBox(
              width: c.maxWidth >= 800
                  ? (c.maxWidth - 32) / 3
                  : c.maxWidth >= 550
                  ? (c.maxWidth - 16) / 2
                  : c.maxWidth,
              child: _fieldWidget(key),
            ),
        ],
      ),
    ),
  );
}
