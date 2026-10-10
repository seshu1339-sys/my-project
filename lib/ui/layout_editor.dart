import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'layout_settings.dart';
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
                DropdownMenuItem(value: item.key, child: Text(item.value)),
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

/// The field-editing body for one layout component: builds one
/// `TextFormField` per applicable key (from `componentFields`), validates,
/// and saves/resets to `settings/section_<component>`. Split out of
/// `LayoutSettingsPage` so the admin Visual Editor can mount it inline,
/// directly beside the live preview, without the dropdown/page chrome —
/// `LayoutSettingsPage` above is now just that chrome wrapping this widget,
/// with identical behavior to before the split.
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
  // edit debounces into a real save a moment after the admin stops typing,
  // instead of waiting for an explicit "Save layout" tap — so the preview
  // reflects changes "instantly" using the exact same, already-validated
  // save() path, not a second persistence mechanism. LayoutSettingsPage
  // (the plain full-page form) leaves this false/unchanged.
  final bool autoSave;
  @override
  State<LayoutFieldsForm> createState() => LayoutFieldsFormState();
}

class LayoutFieldsFormState extends State<LayoutFieldsForm> {
  final form = GlobalKey<FormState>();
  Map<String, TextEditingController> controllers = {};
  bool busy = false;
  bool dirty = false;
  Timer? _debounce;
  Entry get saved => sectionConfig(widget.store.entries('settings'), widget.component);

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
    controllers = {
      for (final key in [
        ...componentFields(widget.component),
        'backgroundColor',
        if (componentFields(widget.component).contains('fontSize')) 'textColor',
        'borderColor',
        if (componentFields(widget.component).contains('fontSize')) 'fontFamily',
        if (['notice', 'ads', 'boxes'].contains(widget.component)) 'direction',
        if (['ads', 'boxes'].contains(widget.component)) 'scrollEnabled',
        if (['products', 'popular', 'localServices'].contains(widget.component)) 'alignment',
      ])
        key: TextEditingController(text: saved.text(key)),
    };
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

  Map<String, dynamic> values() => {
    ...saved.data,
    for (final field in controllers.entries)
      if (field.value.text.trim().isNotEmpty)
        field.key: dimensionFields.containsKey(field.key)
            ? double.tryParse(field.value.text) ?? 0
            : field.value.text.trim(),
  }..removeWhere((key, _) => controllers[key]?.text.trim().isEmpty == true);

  Future<bool> save({bool reset = false}) async {
    if (!reset && !form.currentState!.validate()) return false;
    setState(() => busy = true);
    try {
      final data = values();
      for (final axis in ['Width', 'Height']) {
        final min = (data['min$axis'] as num?) ?? 0;
        final max = (data['max$axis'] as num?) ?? 0;
        if (!reset && max > 0 && min > max) {
          throw StateError('Minimum $axis must not exceed maximum $axis.');
        }
      }
      if (reset) {
        final preserved = Map<String, dynamic>.from(saved.data);
        for (final key in controllers.keys) {
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
        if (reset) {
          for (final controller in controllers.values) {
            controller.clear();
          }
        }
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

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: LayoutBuilder(
      builder: (context, c) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final field in controllers.entries)
            SizedBox(
              width: c.maxWidth >= 800
                  ? (c.maxWidth - 32) / 3
                  : c.maxWidth >= 550
                  ? (c.maxWidth - 16) / 2
                  : c.maxWidth,
              child: TextFormField(
                key: ValueKey('${widget.component}-${field.key}'),
                controller: field.value,
                decoration: InputDecoration(
                  labelText:
                      dimensionFields[field.key]?.$1 ??
                      {
                        'backgroundColor': 'Background (#RRGGBB)',
                        'textColor': 'Text color (#RRGGBB)',
                        'borderColor': 'Border color (#RRGGBB)',
                        'fontFamily': 'Font family',
                        'direction': widget.component == 'notice'
                            ? 'Direction (rtl / ltr)'
                            : 'Scroll direction (up / down)',
                        'scrollEnabled': 'Scroll enabled — pause with false (true / false)',
                        'alignment': 'Grid alignment (start / center / end / spaceBetween)',
                      }[field.key],
                  helperText: dimensionFields.containsKey(field.key)
                      ? '${dimensionFields[field.key]!.$2} – ${dimensionFields[field.key]!.$3}'
                      : null,
                ),
                keyboardType: dimensionFields.containsKey(field.key)
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                onChanged: (_) => _onFieldChanged(),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final rule = dimensionFields[field.key];
                  if (rule != null) {
                    final number = double.tryParse(text);
                    if (number == null ||
                        !number.isFinite ||
                        number < rule.$2 ||
                        number > rule.$3) {
                      return 'Use ${rule.$2} to ${rule.$3}';
                    }
                    if ([
                          'columns',
                          'visibleCount',
                          'rows',
                          'mobileColumns',
                          'tabletColumns',
                          'desktopColumns',
                          'mobileRows',
                          'tabletRows',
                          'desktopRows',
                        ].contains(field.key) &&
                        number != number.round()) {
                      return 'Use a whole number';
                    }
                  } else if (field.key.endsWith('Color') &&
                      !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) {
                    return 'Use #RRGGBB';
                  } else if (field.key == 'direction' &&
                      !(widget.component == 'notice'
                              ? ['rtl', 'ltr']
                              : ['up', 'down'])
                          .contains(text)) {
                    return widget.component == 'notice' ? 'Use rtl or ltr' : 'Use up or down';
                  } else if (field.key == 'scrollEnabled' &&
                      !['true', 'false'].contains(text)) {
                    return 'Use true or false';
                  } else if (field.key == 'alignment' &&
                      !['start', 'center', 'end', 'spaceBetween'].contains(text)) {
                    return 'Use start, center, end or spaceBetween';
                  }
                  return null;
                },
              ),
            ),
        ],
      ),
    ),
  );
}
