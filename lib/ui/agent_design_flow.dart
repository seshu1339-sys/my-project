import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/agent_command.dart';
import '../domain/agent_registry.dart';
import '../domain/catalog.dart';
import '../domain/design_change.dart';
import '../services/agent_log.dart';
import 'agent_hooks.dart';
import 'design_pages.dart';
export 'design_pages.dart';
import 'shared.dart';

/// The command box's design flow (owner spec E): the property the words name (the 3 best when unclear), then [DesignChangePage].
Future<void> openDesignFlow(BuildContext context, Store store, AgentCommand command, List<RegistryEntry> matches, AgentPlatform? platform) async {
  if (matches.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Which part? Say it with the part, e.g. "search box camera icon size 30" or "Today\'s Offers background colour red".')));
    return;
  }
  var entry = matches.first;
  if (matches.length > 1) {
    final picked = await showDialog<RegistryEntry>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Which one? (ఏది?)'),
        children: [
          for (final m in matches.take(3))
            SimpleDialogOption(
              key: ValueKey('design-pick-${m.id}'),
              onPressed: () => Navigator.pop(d, m),
              child: ListTile(title: Text(m.name), subtitle: Text('${m.platforms.map((p) => p.label).join(' · ')} — ${m.what}')),
            ),
        ],
      ),
    );
    if (picked == null) return;
    entry = picked;
  }
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => DesignChangePage(store: store, entry: entry, command: command)));
}

/// One design property: its current value, the question ("which colour?", "how much wider?") with the safe range, a preview of before
/// and after, warnings when it may break the layout, and Save only on OK. The change goes to the history (one tap undoes it).
class DesignChangePage extends StatefulWidget {
  const DesignChangePage({super.key, required this.store, required this.entry, required this.command, this.saveHistory});
  final Store store;
  final RegistryEntry entry;
  final AgentCommand command;

  /// Test seam: the history line (Firestore designHistory when live).
  final Future<void> Function(Map<String, Object?> row)? saveHistory;

  @override
  State<DesignChangePage> createState() => _DesignChangePageState();
}

class _DesignChangePageState extends State<DesignChangePage> {
  late final kind = designKindOf(widget.entry);
  late final target = designTargetOf(widget.entry);
  late final value = TextEditingController(text: proposedValue(kind, widget.command.value, _current, text: widget.command.text) ?? '');
  ({String value, List<String> warnings})? fitted;
  String? done;
  bool busy = false;

  Store get store => widget.store;
  Entry get _record => store.entries('settings').where((e) => e.id == target.record).firstOrNull ?? Entry(target.record, const {});
  Object? get _current => _record.data[target.field] ?? designFields.where((f) => f.id == target.field).firstOrNull?.defaultValue;

  @override
  void dispose() {
    value.dispose();
    super.dispose();
  }

  void _preview() => setState(() {
    fitted = fitDesignValue(widget.entry, kind, value.text, current: _current);
    done = null;
  });

  Future<void> _save() async {
    final f = fitted ?? fitDesignValue(widget.entry, kind, value.text, current: _current);
    final before = _current;
    final Object after = kind == DesignValueKind.number ? (double.tryParse(f.value) ?? 0) : f.value;
    setState(() => busy = true);
    try {
      await store.save('settings', Entry(target.record, {..._record.data, if (_record.data['name'] == null) 'name': _recordName, target.field: after}));
      final row = <String, Object?>{
        'entryId': widget.entry.id, 'name': widget.entry.name, 'recordId': target.record, 'field': target.field,
        'before': before, 'after': after, 'command': widget.command.text, 'by': store.user?.uid ?? '', 'undone': false,
      };
      await (widget.saveHistory ?? (r) async {
        if (store.live) await store.firestore.collection('designHistory').add({...r, 'at': FieldValue.serverTimestamp()});
      })(row);
      AgentLog.write(store, action: 'design_change', command: widget.command.text, target: widget.entry.id, details: {'before': '$before', 'after': '$after'});
      if (!mounted) return;
      final line = describeChange(widget.entry, before, '$after');
      // The box shows what was saved (a value outside the safe range was fitted into it).
      setState(() { done = line; fitted = null; value.text = f.value; });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text('Changed: $line'),
        action: SnackBarAction(label: 'Undo', onPressed: () => undoDesign(store, target.record, target.field, before, entryId: widget.entry.id)),
      ));
    } catch (e) {
      if (mounted) setState(() => done = 'Not saved: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  String get _recordName => switch (target.record) { 'design' => 'Design texts & sizes', 'androidSizes' => 'Android app sizes', _ => target.record };

  Widget _question() {
    final e = widget.entry;
    switch (kind) {
      case DesignValueKind.color:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Which colour? (ఏ రంగు?)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in const ['red', 'green', 'blue', 'yellow', 'orange', 'pink', 'purple', 'brown', 'grey', 'black', 'white'])
              InkWell(
                key: ValueKey('design-colour-$c'),
                onTap: () => setState(() { value.text = agentColorNames[c]!; fitted = null; }),
                child: Tooltip(message: c, child: CircleAvatar(radius: 16, backgroundColor: colorFromHex(agentColorNames[c]!, Colors.black), child: value.text == agentColorNames[c] ? const Icon(Icons.check, size: 16, color: Colors.white) : null)),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(key: const ValueKey('design-value'), controller: value, onChanged: (_) => setState(() => fitted = null), decoration: const InputDecoration(labelText: 'Or a colour code (#FFD32F2F)', border: OutlineInputBorder(), isDense: true)),
        ]);
      case DesignValueKind.number:
        final n = double.tryParse(value.text) ?? double.tryParse('${_current ?? ''}') ?? e.min ?? 0;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.isNumber ? 'How much? Safe range ${_s(e.min!)} to ${_s(e.max!)}.' : 'How much?', key: const ValueKey('design-range'), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (e.isNumber)
            Slider(
              key: const ValueKey('design-slider'),
              value: n.clamp(e.min!, e.max!).toDouble(),
              min: e.min!,
              max: e.max!,
              onChanged: (v) => setState(() { value.text = _s(v.roundToDouble()); fitted = null; }),
            ),
          Row(children: [
            Expanded(child: TextField(key: const ValueKey('design-value'), controller: value, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() => fitted = null), decoration: const InputDecoration(labelText: 'New value', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 8),
            for (final step in const [-10, -1, 1, 10])
              TextButton(onPressed: () => setState(() { value.text = _s((double.tryParse(value.text) ?? n) + step); fitted = null; }), child: Text(step > 0 ? '+$step' : '$step')),
          ]),
        ]);
      case DesignValueKind.toggle:
        return SwitchListTile(key: const ValueKey('design-toggle'), title: const Text('Show it'), value: value.text != 'false', onChanged: (v) => setState(() { value.text = '$v'; fitted = null; }));
      case DesignValueKind.text:
        return TextField(key: const ValueKey('design-value'), controller: value, maxLength: 80, onChanged: (_) => setState(() => fitted = null), decoration: const InputDecoration(labelText: 'What text? (ఏ పేరు / టెక్స్ట్?)', border: OutlineInputBorder(), isDense: true));
    }
  }

  static String _s(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final f = fitted;
    return Scaffold(
      appBar: AppBar(title: const Text('Design change')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.command.text.isNotEmpty) Text('"${widget.command.text}"', style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Text(e.name, key: const ValueKey('design-name'), style: Theme.of(context).textTheme.titleLarge),
          Text('${e.path}\n${e.platforms.map((p) => p.label).join(' + ')} · saved in settings/${target.record}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Text('Now: ${'${_current ?? ''}'.isEmpty ? '(default)' : _current}', key: const ValueKey('design-current')),
          const SizedBox(height: 16),
          _question(),
          const SizedBox(height: 16),
          if (f == null)
            FilledButton.icon(key: const ValueKey('design-preview-button'), onPressed: value.text.trim().isEmpty ? null : _preview, icon: const Icon(Icons.preview_outlined), label: const Text('PREVIEW'))
          else ...[
            Card(
              key: const ValueKey('design-preview'),
              color: const Color(0xFFF1F8E9),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('PREVIEW', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  _BeforeAfter(kind: kind, field: target.field, before: _current, after: f.value),
                  for (final w in f.warnings)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18), const SizedBox(width: 6), Expanded(child: Text(w, key: const ValueKey('design-warning')))])),
                  const SizedBox(height: 8),
                  Text('Will change: ${describeChange(e, _current, f.value)}', key: const ValueKey('design-will-change')),
                  const SizedBox(height: 8),
                  Row(children: [
                    FilledButton.icon(key: const ValueKey('design-ok'), onPressed: busy ? null : _save, icon: const Icon(Icons.check), label: const Text('OK — save')),
                    const SizedBox(width: 12),
                    TextButton(onPressed: () => setState(() => fitted = null), child: const Text('Change')),
                    const Spacer(),
                    if (agentOpenById != null) TextButton.icon(onPressed: () => agentOpenById!(context, store, e.id, command: widget.command.text), icon: const Icon(Icons.open_in_new, size: 16), label: const Text('Open the full form')),
                  ]),
                ]),
              ),
            ),
          ],
          if (done != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(done!.startsWith('Not saved') ? done! : 'Changed: $done', key: const ValueKey('design-done'), style: TextStyle(color: done!.startsWith('Not saved') ? Colors.red : Colors.green, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// Before and after, side by side: two colour samples, two sizes drawn to scale, or two texts.
class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({required this.kind, required this.field, required this.before, required this.after});
  final DesignValueKind kind;
  final String field;
  final Object? before;
  final String after;

  Widget _one(String label, Object? v) {
    final s = '${v ?? ''}';
    final Widget sample = switch (kind) {
      DesignValueKind.color => Container(width: 120, height: 44, decoration: BoxDecoration(color: colorFromHex(s, const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black26)), alignment: Alignment.center, child: Text(s.isEmpty ? 'default' : s, style: const TextStyle(fontSize: 10, color: Colors.black54))),
      DesignValueKind.number => _size(double.tryParse(s) ?? 0),
      DesignValueKind.toggle => Icon(s == 'false' ? Icons.visibility_off : Icons.visibility, size: 32),
      DesignValueKind.text => Container(constraints: const BoxConstraints(maxWidth: 220), padding: const EdgeInsets.all(8), decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)), child: Text(s.isEmpty ? '(default)' : s)),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12)), const SizedBox(height: 4), sample]);
  }

  Widget _size(double n) {
    if (field.contains('font') || field.contains('Font')) return Text('Aa', style: TextStyle(fontSize: n <= 0 ? 14 : n.clamp(6, 60)));
    if (field.toLowerCase().contains('icon')) return Icon(Icons.photo_camera_outlined, size: n <= 0 ? 24 : n.clamp(8, 64));
    final w = n <= 0 ? 0.0 : (n / 8).clamp(4, 240).toDouble();
    return Row(children: [Container(width: w, height: 18, color: const Color(0xFF90CAF9)), const SizedBox(width: 6), Text(n <= 0 ? 'auto' : '${n.round()}')]);
  }

  @override
  Widget build(BuildContext context) => Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [_one('Before', before), const Icon(Icons.arrow_forward), _one('After', after)]);
}

