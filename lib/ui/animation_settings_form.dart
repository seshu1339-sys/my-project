import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'animation_settings.dart';
import 'home_rotating_pages.dart';
import 'layout_settings.dart';
import 'shared.dart';

/// Settings -> Animations: switch the website's animations on or off (everywhere, or for one part of the page), choose
/// fade / slide / zoom and set the speed. It writes ONE record, `settings/animations`; nothing here changes a part's own layout
/// settings, and with nothing chosen the site looks exactly as before (see lib/ui/animation_settings.dart).
class AdminAnimationsForm extends StatefulWidget {
  const AdminAnimationsForm({super.key, required this.store});
  final Store store;
  @override
  State<AdminAnimationsForm> createState() => _AdminAnimationsFormState();
}

class _AdminAnimationsFormState extends State<AdminAnimationsForm> {
  late Map<String, dynamic> values; // only what the admin set; a missing key means "as before"
  bool busy = false;
  int previewRun = 0;
  String previewType = 'fade';
  int previewSpeed = 5;

  @override
  void initState() {
    super.initState();
    values = {...animationsDoc(widget.store.entries('settings')).data}..remove('name');
  }

  String text(String key, [String fallback = '']) {
    final v = values[key];
    return v == null || '$v'.isEmpty ? fallback : '$v';
  }

  void _set(String key, Object? value) => setState(() {
    if (value == null || '$value'.isEmpty) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  });

  bool get _globalOn => text('enabled', 'true') != 'false';

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.store.save('settings', Entry('animations', {'name': 'Animations', ...values}));
      if (mounted) message(context, 'Animations saved. Open pages update at once; the site picks it up on its next load.');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _typeDropdown(String key, {required String keepLabel}) => DropdownButtonFormField<String>(
    key: ValueKey('$key-${text(key)}'),
    initialValue: entranceTypes.containsKey(text(key)) ? text(key) : '',
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Animation', isDense: true, border: OutlineInputBorder()),
    items: [
      DropdownMenuItem(value: '', child: Text(keepLabel)),
      for (final e in entranceTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
    ],
    onChanged: (v) => _set(key, v),
  );

  Widget _speedDropdown(String key, {required String unsetLabel}) {
    final current = int.tryParse(text(key));
    return DropdownButtonFormField<int?>(
      key: ValueKey('$key-$current'),
      initialValue: current != null && current >= 1 && current <= 10 ? current : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Speed', isDense: true, border: OutlineInputBorder()),
      items: [
        DropdownMenuItem<int?>(value: null, child: Text(unsetLabel)),
        for (var s = 1; s <= 10; s++) DropdownMenuItem<int?>(value: s, child: Text(s == 1 ? '1 (slowest)' : s == 10 ? '10 (fastest)' : '$s')),
      ],
      onChanged: (v) => _set(key, v),
    );
  }

  Widget _partCard(String part, String label) {
    final on = text('${part}_enabled', 'true') != 'false';
    return Card(
      key: ValueKey('anim-card-$part'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: ValueKey('anim-$part-enabled'),
              contentPadding: EdgeInsets.zero,
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(!_globalOn ? 'Off: all animations are switched off above' : on ? 'Animations on' : 'Animations off for this part'),
              value: on && _globalOn,
              onChanged: _globalOn ? (v) => _set('${part}_enabled', v ? null : 'false') : null,
            ),
            if (on && _globalOn)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(width: 240, child: KeyedSubtree(key: ValueKey('anim-$part-type'), child: _typeDropdown('${part}_type', keepLabel: 'Keep its current setting'))),
                  SizedBox(width: 200, child: KeyedSubtree(key: ValueKey('anim-$part-speed'), child: _speedDropdown('${part}_speed', unsetLabel: 'Default speed'))),
                  if (rotatingParts.contains(part))
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('anim-$part-rotation-${text('${part}_rotation')}'),
                        initialValue: promoAnimationLabels.containsKey(text('${part}_rotation')) ? text('${part}_rotation') : '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'How the pictures change', isDense: true, border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('Keep its current setting')),
                          for (final e in promoAnimationLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => _set('${part}_rotation', v),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Animations', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text(
        'Switch the website\'s animations on or off, everywhere or for one part, and choose the type and speed. '
        'Nothing changes until you choose something here.',
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const ValueKey('anim-global-enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Animations on the website', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Off stops every animation: entrances, banner changes and animated texts.'),
                value: _globalOn,
                onChanged: (v) => _set('enabled', v ? null : 'false'),
              ),
              if (_globalOn)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(width: 280, child: KeyedSubtree(key: const ValueKey('anim-default-type'), child: _typeDropdown('defaultType', keepLabel: 'Each part keeps its own'))),
                    SizedBox(width: 220, child: KeyedSubtree(key: const ValueKey('anim-default-speed'), child: _speedDropdown('defaultSpeed', unsetLabel: 'Original speed'))),
                  ],
                ),
              if (_globalOn)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('The default type is used by parts that have no animation of their own.', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text('Each part of the page', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final part in animationParts.entries) _partCard(part.key, part.value),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Try it', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('anim-preview-type'),
                  isExpanded: true,
                  initialValue: previewType,
                  decoration: const InputDecoration(labelText: 'Type', isDense: true, border: OutlineInputBorder()),
                  items: [for (final e in entranceTypes.entries) if (e.key != 'none') DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => previewType = v ?? 'fade'),
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('anim-preview-speed'),
                  isExpanded: true,
                  initialValue: previewSpeed,
                  decoration: const InputDecoration(labelText: 'Speed', isDense: true, border: OutlineInputBorder()),
                  items: [for (var s = 1; s <= 10; s++) DropdownMenuItem(value: s, child: Text('$s'))],
                  onChanged: (v) => setState(() => previewSpeed = v ?? 5),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('anim-preview-play'),
                onPressed: () => setState(() => previewRun++),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              KeyedSubtree(
                key: ValueKey('anim-preview-$previewRun'),
                child: applyEntranceAnimation(
                  Entry('preview', {'animation': previewType, 'entranceMs': entranceMillis(previewSpeed)}),
                  Container(width: 56, height: 56, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          FilledButton(key: const ValueKey('anim-save'), onPressed: busy ? null : save, child: Text(busy ? 'Saving…' : 'Save animations')),
        ],
      ),
    ],
  );
}
