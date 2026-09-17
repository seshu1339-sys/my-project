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
  final form = GlobalKey<FormState>();
  String component = 'search';
  Map<String, TextEditingController> controllers = {};
  bool busy = false;
  bool dirty = false;
  Entry get saved => sectionConfig(widget.store.entries('settings'), component);
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    controllers = {
      for (final key in [
        ...componentFields(component),
        'backgroundColor',
        if (componentFields(component).contains('fontSize')) 'textColor',
        'borderColor',
        if (componentFields(component).contains('fontSize')) 'fontFamily',
        if (component == 'notice') 'direction',
        if (['ads', 'boxes'].contains(component)) 'scrollEnabled',
      ])
        key: TextEditingController(text: saved.text(key)),
    };
    dirty = false;
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
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
          Entry('section_$component', preserved),
        );
      } else {
        await widget.store.save(
          'settings',
          Entry('section_$component', {...data, 'section': component}),
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
                onPressed: busy ? null : () => save(),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save layout'),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => save(reset: true),
                child: const Text('Reset this component to default'),
              ),
            ],
          ),
        ),
      ),
      body: Form(
        key: form,
        child: ListView(
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
              onChanged: busy
                  ? null
                  : (value) async {
                      if (value == null || value == component) return;
                      if (dirty && !await save()) return;
                      if (mounted) {
                        setState(() {
                          component = value;
                          load();
                        });
                      }
                    },
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
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
                        key: ValueKey('$component-${field.key}'),
                        controller: field.value,
                        decoration: InputDecoration(
                          labelText:
                              dimensionFields[field.key]?.$1 ??
                              {
                                'backgroundColor': 'Background (#RRGGBB)',
                                'textColor': 'Text color (#RRGGBB)',
                                'borderColor': 'Border color (#RRGGBB)',
                                'fontFamily': 'Font family',
                                'direction': 'Direction (rtl / ltr)',
                                'scrollEnabled': 'Scroll upward (true / false)',
                              }[field.key],
                          helperText: dimensionFields.containsKey(field.key)
                              ? '${dimensionFields[field.key]!.$2} – ${dimensionFields[field.key]!.$3}'
                              : null,
                        ),
                        keyboardType: dimensionFields.containsKey(field.key)
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        onChanged: (_) {
                          dirty = true;
                        },
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
                                ].contains(field.key) &&
                                number != number.round()) {
                              return 'Use a whole number';
                            }
                          } else if (field.key.endsWith('Color') &&
                              !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) {
                            return 'Use #RRGGBB';
                          } else if (field.key == 'direction' &&
                              !['rtl', 'ltr'].contains(text)) {
                            return 'Use rtl or ltr';
                          } else if (field.key == 'scrollEnabled' &&
                              !['true', 'false'].contains(text)) {
                            return 'Use true or false';
                          }
                          return null;
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
