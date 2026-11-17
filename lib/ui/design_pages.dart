import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/design_change.dart';
import '../services/agent_log.dart';
import 'agent_focus.dart';

/// Puts a value back (one-click undo): the field gets [before] again (removed when there was none) and the history line is marked.
Future<void> undoDesign(Store store, String record, String field, Object? before, {String entryId = '', String historyId = ''}) async {
  final current = store.entries('settings').where((e) => e.id == record).firstOrNull ?? Entry(record, const {});
  final data = {...current.data};
  if (before == null || '$before'.isEmpty) {
    data.remove(field);
  } else {
    data[field] = before;
  }
  await store.save('settings', Entry(record, data));
  if (store.live && historyId.isNotEmpty) {
    await store.firestore.collection('designHistory').doc(historyId).update({'undone': true, 'undoneAt': FieldValue.serverTimestamp()});
  }
  AgentLog.write(store, action: 'design_undo', target: entryId.isEmpty ? '$record.$field' : entryId, details: {'restored': '${before ?? ''}'});
}

/// Settings > Design history: every design change, newest first, with one-click Undo.
class DesignHistoryPage extends StatelessWidget {
  const DesignHistoryPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    if (!store.live) return const Center(child: Text('The design history is kept in the live panel.'));
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('designHistory').orderBy('at', descending: true).limit(100).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = [for (final d in snap.data!.docs) DesignChange.from(d.id, d.data())];
        if (rows.isEmpty) return const Center(child: Text('No design changes yet.'));
        return ListView(children: [
          for (final r in rows)
            ListTile(
              key: ValueKey('design-history-${r.id}'),
              leading: Icon(r.undone ? Icons.undo : Icons.palette_outlined),
              title: Text('${r.name}: ${'${r.before ?? ''}'.isEmpty ? '(default)' : r.before} → ${r.after}'),
              subtitle: Text([if (r.command.isNotEmpty) '"${r.command}"', if (r.at != null) '${r.at!.toLocal()}'.split('.').first, if (r.undone) 'undone'].join(' · ')),
              trailing: r.undone
                  ? null
                  : TextButton(key: ValueKey('design-undo-${r.id}'), onPressed: () => undoDesign(store, r.record, r.field, r.before, entryId: r.entryId, historyId: r.id), child: const Text('Undo')),
            ),
        ]);
      },
    );
  }
}

/// Settings > Design texts & sizes: the values that were fixed in the code (right-side ad box height, Today's Offers texts), now
/// editable here and by command; the website and the apps read them from settings/design.
class DesignTextsPage extends StatefulWidget {
  const DesignTextsPage({super.key, required this.store});
  final Store store;
  @override
  State<DesignTextsPage> createState() => _DesignTextsPageState();
}

class _DesignTextsPageState extends State<DesignTextsPage> {
  late final Entry record = widget.store.entries('settings').where((e) => e.id == designRecordId).firstOrNull ?? const Entry(designRecordId, {});
  late final controllers = {for (final f in designFields) f.id: TextEditingController(text: '${record.data[f.id] ?? ''}')};
  String? note;

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final data = {...record.data, 'name': 'Design texts & sizes'};
    for (final f in designFields) {
      final t = controllers[f.id]!.text.trim();
      if (t.isEmpty) {
        data.remove(f.id);
      } else if (f.isNumber) {
        data[f.id] = (double.tryParse(t) ?? (f.defaultValue as double)).clamp(f.min!, f.max!);
      } else {
        data[f.id] = t;
      }
    }
    await widget.store.save('settings', Entry(designRecordId, data));
    AgentLog.write(widget.store, action: 'design_texts_saved');
    if (mounted) setState(() => note = 'Saved. The website and the apps show it on their next open.');
  }

  @override
  Widget build(BuildContext context) => AgentFormList(
    padding: const EdgeInsets.all(20),
    children: [
      const Text('Values that used to be fixed in the app. Blank = the default. The website and the Android apps read them from the server.'),
      const SizedBox(height: 16),
      for (final f in designFields)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: AgentFocusTarget(
            fieldKey: f.id,
            child: TextField(
              key: ValueKey('design-text-${f.id}'),
              controller: controllers[f.id],
              keyboardType: f.isNumber ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(labelText: f.label, helperText: f.isNumber ? 'Default ${f.defaultValue} · safe ${_n(f.min!)} to ${_n(f.max!)}' : 'Default: ${f.defaultValue}', border: const OutlineInputBorder()),
            ),
          ),
        ),
      FilledButton(key: const ValueKey('design-texts-save'), onPressed: _save, child: const Text('Save')),
      if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note!)),
    ],
  );

  static String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
}
