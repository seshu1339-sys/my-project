import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'color_picker_field.dart';
import 'design_tokens.dart';
import 'entry_editor.dart';
import 'home_rotating_pages.dart';
import 'layout_settings.dart';
import 'reset_confirmation.dart';
import 'text_animation.dart';
import 'home_section_config.dart';
import 'page_elements.dart';
import 'shared.dart';

// Fields that hold an image URL and so get a real Upload/Remove image pair
// next to their plain URL text field (same ImagePicker + Store.upload path
// entry_editor.dart's collection forms already use) -- not just a box to
// paste a URL into.
const _imageUrlFields = {'iconUrl', 'backgroundImage'};

/// The Layout Settings dropdown: every component, in the admin's element-number
/// order (1, 2, 3 ... 14, 15 ...), so numbers never appear out of sequence.
/// "Header" (no number) comes first, a group's members (footer badges 28.1 ..
/// 28.6) right after their group, "Page layout" after them, and the other
/// screens' numbered elements (29+) follow. Includes the ticker banner (14),
/// which is edited in its own editor ([externalLayoutComponents]).
List<MapEntry<String, String>> layoutComponentChoices() {
  final all = [...layoutComponents.entries, ...externalLayoutComponents.entries];
  double rank(String key, int index) {
    if (key == 'header') return 0;
    final badge = RegExp(r'^footerBadge(\d)$').firstMatch(key);
    if (badge != null) return 28 + int.parse(badge.group(1)!) / 10;
    if (key == 'background') return 28.95;
    final element = pageElementByKey(key);
    return element != null ? element.number.toDouble() : 1000 + index.toDouble();
  }

  final ranked = [for (final (i, entry) in all.indexed) (rank(entry.key, i), i, entry)]
    ..sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
    });
  return [for (final item in ranked) item.$3];
}

class LayoutSettingsPage extends StatefulWidget {
  const LayoutSettingsPage({super.key, required this.store});
  final Store store;
  @override
  State<LayoutSettingsPage> createState() => _LayoutSettingsPageState();
}

class _LayoutSettingsPageState extends State<LayoutSettingsPage> {
  final formKey = GlobalKey<LayoutFieldsFormState>();
  String component = 'search';

  /// The ticker banner (14): its size, colors, text and speed are in the
  /// Scrolling Text Settings editor, not a layout form.
  Widget _externalEditorPanel() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This is the scrolling text banner at the top of the home page. '
            'Its text, colors, font, size and speed are set in Scrolling Text Settings.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('open-scrolling-text-settings'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Scrolling Text Settings'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EntryEditor(
                  store: widget.store,
                  collection: 'scrollingText',
                  entry: widget.store
                      .entries('settings')
                      .where((e) => e.id == 'scrollingText')
                      .firstOrNull,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

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
      bottomNavigationBar: externalLayoutComponents.containsKey(component)
          ? null
          : SafeArea(
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
                onPressed: () => formKey.currentState?.resetToDefault(),
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
              for (final item in layoutComponentChoices())
                DropdownMenuItem(
                  value: item.key,
                  child: Text(numberedLabel(item.key, item.value)),
                ),
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
          if (externalLayoutComponents.containsKey(component))
            _externalEditorPanel()
          else
            LayoutFieldsForm(
              key: formKey,
              store: widget.store,
              component: component,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// How one field's value is edited — picked once per key by _kindOf below,
// not per component, so every component's form stays consistent.
enum _FieldKind {
  toggle,
  color,
  fontFamily,
  fontStyle,
  fontWeight,
  animation,
  animationType,
  textAnimation,
  alignment,
  direction,
  number,
  text,
}

const _toggleLabels = {
  'visible': 'Visible on the site',
  'scrollEnabled': 'Scroll enabled',
  'pauseOnTouch': 'Pause when touched or hovered',
};

_FieldKind _kindOf(String key) {
  if (_toggleLabels.containsKey(key)) return _FieldKind.toggle;
  if (key.endsWith('Color') || key == 'gradientStart' || key == 'gradientEnd')
    return _FieldKind.color;
  if (key == 'fontFamily') return _FieldKind.fontFamily;
  if (key == 'fontStyle') return _FieldKind.fontStyle;
  if (key == 'fontWeight') return _FieldKind.fontWeight;
  if (key == 'animation') return _FieldKind.animation;
  if (key == 'animationType') return _FieldKind.animationType;
  if (key == 'textAnimation' || key == 'headingAnimation') {
    return _FieldKind.textAnimation;
  }
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
    this.fieldsOverride,
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
  // When set, shows exactly these fields instead of allFieldsFor's usual
  // design list -- used by the dedicated "<Section> Settings" pages
  // (behavior fields like speed/direction/scrollEnabled, intentionally
  // kept out of the numbered Design panels) to reuse this same form/save
  // machinery for a different field set on the SAME settings/section_*
  // doc, rather than building a near-duplicate.
  final List<String>? fieldsOverride;
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
  final advancedController = ExpansibleController();
  Timer? _debounce;
  int _animationPreviewTick = 0;
  Entry get saved =>
      sectionConfig(widget.store.entries('settings'), widget.component);
  List<String> get fields =>
      widget.fieldsOverride ?? allFieldsFor(widget.component);

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
          // 'visible' defaults to true when unset for most components
          // (componentVisible delegates to sectionVisible's own rule for
          // them), false for the few that default to hidden (e.g.
          // 'adsLabel' -- see home_section_config.dart); 'scrollEnabled'
          // defaults to false (see home_scheduled_promo.dart's own default
          // — flipped from true after the ad/box overlap fix). Entry.text()
          // normalizes a legacy string 'true'/'false' the same as a real
          // stored bool.
          values[key] = key == 'visible'
              ? componentVisible(saved, widget.component)
              : saved.text(key, key == 'pauseOnTouch' ? 'true' : 'false') ==
                    'true';
        case _FieldKind.color:
        case _FieldKind.fontFamily:
        case _FieldKind.fontStyle:
        case _FieldKind.fontWeight:
        case _FieldKind.animation:
        case _FieldKind.animationType:
        case _FieldKind.textAnimation:
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

  // Same ImagePicker + Store.upload path entry_editor.dart's own "Upload
  // image" button already uses for collection entries (products,
  // categories, promotions, ...) -- reused here so a layout-component
  // image field (icon replace, or the ticker's new background photo) gets
  // a real upload, not just a box to paste a URL into.
  Future<void> _uploadImage(String key) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      setState(() => busy = true);
      final url = await widget.store.upload(file);
      if (mounted) {
        setState(() => controllers[key]!.text = url);
        _onFieldChanged();
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _clearImage(String key) {
    setState(() => controllers[key]!.clear());
    _onFieldChanged();
  }

  Map<String, dynamic> _collectValues() {
    final out = <String, dynamic>{...saved.data};
    for (final entry in controllers.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) {
        out.remove(entry.key);
      } else {
        out[entry.key] = dimensionFields.containsKey(entry.key)
            ? (double.tryParse(text) ?? 0)
            : text;
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
    if (!reset) {
      final conflicts = layoutConflicts(_typedNumbers());
      if (conflicts.isNotEmpty) {
        // Show the fields that disagree (they live under Advanced) and say why nothing was saved.
        advancedController.expand();
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => form.currentState?.validate());
        message(context, 'Not saved: ${conflicts.first.message}');
        return false;
      }
      if (!form.currentState!.validate()) {
        advancedController.expand();
        return false;
      }
    }
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
          Entry('section_${widget.component}', {
            ...data,
            'section': widget.component,
          }),
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

  /// What is typed now, as numbers (blank / not a number = 0, automatic).
  Map<String, double> _typedNumbers() => {
    for (final e in controllers.entries)
      if (dimensionFields.containsKey(e.key)) e.key: double.tryParse(e.value.text.trim()) ?? 0,
  };

  /// "Reset this component to default": lists every setting that will change (current -> default), asks, clears them, then reads the
  /// record back from the database to confirm they are gone and says what changed. Returns whether everything was cleared.
  Future<bool> resetToDefault() async {
    final rows = layoutResetRows(saved, widget.component, fields);
    if (rows.isEmpty) {
      message(context, 'Nothing to reset: this component already uses its defaults.');
      return true;
    }
    final name = layoutComponents[widget.component] ?? widget.component;
    final ok = await confirmReset(
      context,
      title: 'Reset $name to default?',
      intro: 'These ${rows.length} ${rows.length == 1 ? 'setting goes' : 'settings go'} back to the default. Anything not listed (behaviour settings, other components) is kept.',
      rows: rows,
    );
    if (!ok || !mounted) return false;
    setState(() => busy = true);
    try {
      final gone = {for (final row in rows) row.key};
      await widget.store.save('settings', Entry('section_${widget.component}', {...saved.data}..removeWhere((k, _) => gone.contains(k))));
      final fresh = await widget.store.freshRecord('settings', 'section_${widget.component}');
      final left = [for (final row in rows) if (fresh != null && fresh.containsKey(row.key)) row];
      dirty = false;
      load();
      widget.onSaved?.call();
      if (mounted) {
        await showResetDone(
          context,
          title: left.isEmpty ? 'Reset complete' : 'Reset incomplete',
          rows: [for (final row in rows) if (!left.contains(row)) row],
          warning: left.isEmpty ? null : 'Could not clear: ${left.map((r) => r.label).join(', ')}. Try again.',
        );
      }
      return left.isEmpty;
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
    if (number == null ||
        !number.isFinite ||
        number < rule.$2 ||
        number > rule.$3) {
      return 'Use ${rule.$2} to ${rule.$3}';
    }
    if ({
          'columns',
          'visibleCount',
          'rows',
          'mobileColumns',
          'tabletColumns',
          'desktopColumns',
          'mobileRows',
          'tabletRows',
          'desktopRows',
        }.contains(key) &&
        number != number.round()) {
      return 'Use a whole number';
    }
    // Two sizes that cannot both be true ("Width 900, Minimum width 1000") are refused, with the reason.
    for (final conflict in layoutConflicts(_typedNumbers())) {
      if (conflict.keys.contains(key)) return conflict.message;
    }
    return null;
  }

  // A slider under every number box: it shows the current value (not just the
  // allowed minimum and maximum) and moves the value as it is dragged.
  Widget _numberSlider(String key) {
    final rule = dimensionFields[key]!;
    final lo = rule.$2, hi = rule.$3;
    final typed = double.tryParse(controllers[key]!.text.trim());
    final decimals = hi - lo <= 3 ? 2 : 0;
    String show(double v) {
      final s = v.toStringAsFixed(decimals);
      return decimals == 0 || !s.contains('.')
          ? s
          : s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    final unit = pixelFields.contains(key) ? ' px' : '';
    final step = decimals == 0 ? 1.0 : (hi - lo <= 1.5 ? .05 : .1);
    final divisions = ((hi - lo) / step).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          typed == null
              ? 'Current value: not set (default)'
              : 'Current value: ${show(typed)}$unit',
          key: ValueKey('${widget.component}-$key-current'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            tickMarkShape: SliderTickMarkShape.noTickMark,
          ),
          child: Slider(
            key: ValueKey('${widget.component}-$key-slider'),
            min: lo,
            max: hi,
            divisions: divisions,
            value: (typed ?? lo).clamp(lo, hi).toDouble(),
            label: show((typed ?? lo).clamp(lo, hi).toDouble()) + unit,
            onChanged: (v) {
              setState(() => controllers[key]!.text = show(v));
              _onFieldChanged();
            },
          ),
        ),
      ],
    );
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
          'notificationIcon',
          'wishlistIcon',
          'cartIcon',
          'menuIcon',
        }.contains(widget.component);
        return ColorPickerField(
          key: ValueKey('${widget.component}-$key'),
          label: key == 'textColor' && isIconOnly
              ? 'Icon color'
              : key == 'textColor' && widget.component == 'search'
              ? 'Typed text color'
              : const {
                  'backgroundColor': 'Background color',
                  'textColor': 'Text color',
                  'borderColor': 'Border color',
                  'searchIconColor': 'Search icon color',
                  'micIconColor': 'Mic icon color',
                  'cameraIconColor': 'Camera icon color',
                  'placeholderColor': 'Placeholder text color',
                  'gradientStart': 'Gradient start',
                  'gradientEnd': 'Gradient end',
                }[key]!,
          value: values[key] as String,
          onChanged: (v) => _setValue(key, v),
        );
      case _FieldKind.fontFamily:
        return DropdownButtonFormField<String>(
          key: ValueKey('${widget.component}-$key'),
          initialValue: (values[key] as String).isEmpty
              ? null
              : values[key] as String,
          decoration: const InputDecoration(labelText: 'Font family'),
          hint: const Text('Theme default'),
          items: [
            for (final f in fontFamilyOptions)
              DropdownMenuItem(value: f, child: Text(f)),
          ],
          onChanged: (v) => _setValue(key, v ?? ''),
        );
      case _FieldKind.fontStyle:
        return DropdownButtonFormField<String>(
          key: ValueKey('${widget.component}-$key'),
          initialValue: (values[key] as String).isEmpty
              ? 'normal'
              : values[key] as String,
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
          initialValue: (values[key] as String).isEmpty
              ? null
              : values[key] as String,
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
          initialValue: (values[key] as String).isEmpty
              ? (isNotice ? 'rtl' : 'up')
              : values[key] as String,
          decoration: InputDecoration(
            labelText: isNotice ? 'Direction' : 'Scroll direction',
          ),
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
      case _FieldKind.animationType:
        return DropdownButtonFormField<String>(
          key: ValueKey('${widget.component}-$key'),
          initialValue: promoAnimationLabels.containsKey(values[key])
              ? values[key] as String
              : '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Animation type'),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('None (original behavior)'),
            ),
            for (final option in promoAnimationLabels.entries)
              DropdownMenuItem(value: option.key, child: Text(option.value)),
          ],
          onChanged: (v) => _setValue(key, v ?? ''),
        );
      case _FieldKind.textAnimation:
        return DropdownButtonFormField<String>(
          key: ValueKey('${widget.component}-$key'),
          initialValue: textAnimationLabels.containsKey(values[key])
              ? values[key] as String
              : '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: key == 'headingAnimation'
                ? '"Today\'s Offers" heading animation'
                : 'Banner text animation (e.g. "Big Savings Everyday")',
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('None')),
            for (final option in textAnimationLabels.entries)
              DropdownMenuItem(value: option.key, child: Text(option.value)),
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
              initialValue: (values[key] as String).isEmpty
                  ? 'none'
                  : values[key] as String,
              decoration: const InputDecoration(
                labelText: 'Entrance animation',
              ),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('None')),
                DropdownMenuItem(value: 'fade', child: Text('Fade in')),
                DropdownMenuItem(
                  value: 'slide',
                  child: Text('Slide + fade in'),
                ),
                DropdownMenuItem(value: 'zoom', child: Text('Zoom in')),
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
                  key: ValueKey(
                    'anim-preview-${widget.component}-$_animationPreviewTick',
                  ),
                  child: applyEntranceAnimation(
                    Entry('preview', {'animation': values[key]}),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTokens.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case _FieldKind.alignment:
        final current = (values[key] as String).isEmpty
            ? 'start'
            : values[key] as String;
        return InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Alignment',
            border: InputBorder.none,
          ),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'start',
                icon: Icon(Icons.format_align_left),
                label: Text('Left'),
              ),
              ButtonSegment(
                value: 'center',
                icon: Icon(Icons.format_align_center),
                label: Text('Center'),
              ),
              ButtonSegment(
                value: 'end',
                icon: Icon(Icons.format_align_right),
                label: Text('Right'),
              ),
            ],
            selected: {current},
            onSelectionChanged: (s) => _setValue(key, s.first),
          ),
        );
      case _FieldKind.number:
      case _FieldKind.text:
        final isPixel = pixelFields.contains(key);
        final field = TextFormField(
          key: ValueKey('${widget.component}-$key'),
          controller: controllers[key],
          decoration: InputDecoration(
            labelText:
                dimensionFields[key]?.$1 ??
                {
                  'fontFamily': 'Font family',
                  'iconUrl': 'Icon image URL (optional)',
                  'backgroundImage':
                      'Background photo URL (optional — or use Upload below)',
                  'text': widget.component == 'office'
                      ? 'Office address and phone (shown exactly as typed)'
                      : 'Text content (optional — leave blank for the default)',
                }[key],
            suffixText: isPixel ? 'px' : null,
            alignLabelWithHint: key == 'text' && widget.component == 'office',
            helperText: dimensionFields.containsKey(key)
                ? '${dimensionFields[key]!.$2} – ${dimensionFields[key]!.$3}'
                : null,
          ),
          keyboardType: dimensionFields.containsKey(key)
              ? const TextInputType.numberWithOptions(decimal: true)
              : key == 'text' && widget.component == 'office'
              ? TextInputType.multiline
              : TextInputType.text,
          minLines: key == 'text' && widget.component == 'office' ? 3 : 1,
          maxLines: key == 'text' && widget.component == 'office' ? 6 : 1,
          onChanged: (_) {
            // A typed number moves its slider; every field still saves as before.
            if (dimensionFields.containsKey(key)) setState(() {});
            _onFieldChanged();
          },
          validator: dimensionFields.containsKey(key)
              ? (v) => _numberValidator(key, v)
              : null,
        );
        if (dimensionFields.containsKey(key)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [field, _numberSlider(key)],
          );
        }
        if (!_imageUrlFields.contains(key)) return field;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            field,
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _uploadImage(key),
                  icon: const Icon(Icons.upload, size: 18),
                  label: const Text('Upload image'),
                ),
                if (controllers[key]!.text.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _clearImage(key),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Remove image'),
                  ),
              ],
            ),
          ],
        );
    }
  }

  /// The pixel sizes and scales: exact numbers for people who want them, kept under "Advanced". The pages that edit a section's
  /// behaviour (speed, direction ...) pass their own field list and are not split.
  bool get _splitAdvanced => widget.fieldsOverride == null;

  void _applyPreset(String preset) {
    for (final e in presetValues(preset, fields).entries) {
      controllers[e.key]?.text = e.value;
    }
    setState(() {});
    _onFieldChanged();
  }

  Widget _presets() {
    final targets = presetValues('medium', fields);
    if (!_splitAdvanced || targets.isEmpty) return const SizedBox.shrink();
    final current = presetOf({for (final e in controllers.entries) e.key: e.value.text}, fields);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Size', style: TextStyle(fontWeight: FontWeight.bold)),
          SegmentedButton<String>(
            key: const ValueKey('size-preset'),
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: 'small', label: Text('Small')),
              ButtonSegment(value: 'medium', label: Text('Medium')),
              ButtonSegment(value: 'large', label: Text('Large')),
            ],
            selected: {?current},
            onSelectionChanged: (s) {
              if (s.isNotEmpty) _applyPreset(s.first);
            },
          ),
          Text(
            current == null ? 'Custom sizes (see Advanced)' : 'Fine-tune in Advanced',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth >= 800
            ? (c.maxWidth - 32) / 3
            : c.maxWidth >= 550
            ? (c.maxWidth - 16) / 2
            : c.maxWidth;
        Widget wrap(Iterable<String> keys) => Wrap(
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [for (final key in keys) SizedBox(width: width, child: _fieldWidget(key))],
        );
        final advanced = [
          if (_splitAdvanced)
            for (final key in fields)
              if (_kindOf(key) == _FieldKind.number) key,
        ];
        final simple = [for (final key in fields) if (!advanced.contains(key)) key];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _presets(),
            wrap(simple),
            if (advanced.isNotEmpty) ...[
              const SizedBox(height: 16),
              ExpansionTile(
                key: ValueKey('advanced-${widget.component}'),
                controller: advancedController,
                maintainState: true,
                tilePadding: EdgeInsets.zero,
                title: const Text('Advanced', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Exact sizes in pixels: width, height, minimum and maximum, spacing, scales'),
                childrenPadding: const EdgeInsets.only(top: 8),
                children: [wrap(advanced)],
              ),
            ],
          ],
        );
      },
    ),
  );
}
