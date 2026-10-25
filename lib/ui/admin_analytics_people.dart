import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/usage_report.dart';
import '../services/file_download.dart';
import '../services/report_export.dart';

/// Admin > Insights > Analytics > People: each signed-in person's use of the apps over the last 7, 30 or 90 days (customers,
/// vendors, service providers, staff), the most active first, with who they are (accountLabels). Opening a person shows what they
/// did and with what (shops, items, searches). The privacy policy tells customers this is kept, and for how long.
class AnalyticsPeopleView extends StatefulWidget {
  const AnalyticsPeopleView({super.key, required this.store, this.load, this.labels});
  final Store store;
  // Test seams: the usagePersonDaily records of a range, and who the account ids are.
  final Future<List<Entry>> Function(String from, String to)? load;
  final Future<Map<String, Map<String, dynamic>>> Function(List<String> uids)? labels;
  @override
  State<AnalyticsPeopleView> createState() => _AnalyticsPeopleViewState();
}

class _AnalyticsPeopleViewState extends State<AnalyticsPeopleView> {
  int days = 30;
  List<PersonUsage> people = const [];
  Map<String, Map<String, dynamic>> who = const {};
  final search = TextEditingController();
  String? error;
  bool loading = true;
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<List<Entry>> _records(String from, String to) async {
    final snapshot = await store.firestore.collection('usagePersonDaily').where('day', isGreaterThanOrEqualTo: from).where('day', isLessThanOrEqualTo: to).limit(5000).get();
    return [for (final d in snapshot.docs) Entry(d.id, d.data())];
  }

  Future<Map<String, Map<String, dynamic>>> _labels(List<String> uids) async {
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < uids.length; i += 100) {
      final result = await store.call('accountLabels', {'uids': uids.sublist(i, (i + 100).clamp(0, uids.length))});
      (result['labels'] as Map? ?? const {}).forEach((k, v) => out['$k'] = Map<String, dynamic>.from(v as Map));
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final now = DateTime.now();
      final rows = await (widget.load ?? _records)(usageDay(now.subtract(Duration(days: days - 1))), usageDay(now));
      final list = PersonUsage.build(rows);
      final labels = await (widget.labels ?? _labels)([for (final p in list.take(300)) p.uid]);
      if (mounted) {
        setState(() {
          people = list;
          who = labels;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'The people report could not load: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _name(String uid) {
    final w = who[uid];
    if (w == null) return uid;
    final parts = [for (final k in ['name', 'email']) if ('${w[k] ?? ''}'.isNotEmpty) '${w[k]}'];
    return parts.isEmpty ? uid : parts.join(' • ');
  }

  List<PersonUsage> get _shown {
    final q = search.text.trim().toLowerCase();
    return [for (final p in people) if (q.isEmpty || p.uid.toLowerCase().contains(q) || _name(p.uid).toLowerCase().contains(q) || '${who[p.uid]?['kind'] ?? ''}'.contains(q)) p];
  }

  ReportTable _table(List<PersonUsage> list) => ReportTable('People, last $days days', ['Person', 'Kind', 'Days active', 'Actions', ...usageEventLabels.values], [
    for (final p in list) [_name(p.uid), '${who[p.uid]?['kind'] ?? ''}', p.days.length, p.total, for (final e in usageEventLabels.keys) p.counts[e] ?? 0],
  ]);

  Future<void> _excel() async {
    final list = _shown;
    final details = ReportTable('What each person did', ['Person', 'What', 'Times'], [
      for (final p in list.take(300)) for (final k in (p.keys.values.toList()..sort((a, b) => b.count.compareTo(a.count)))) [_name(p.uid), k.label, k.count],
    ]);
    try {
      await downloadFile('people-last-$days-days-${usageDay(DateTime.now())}.xlsx', buildXlsx([_table(list), details]), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not download: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _shown;
    return ListView(
      key: const ValueKey('analytics-people'),
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 7, label: Text('7 days')), ButtonSegment(value: 30, label: Text('30 days')), ButtonSegment(value: 90, label: Text('90 days'))],
              selected: {days},
              onSelectionChanged: (v) {
                setState(() => days = v.first);
                _load();
              },
            ),
            FilledButton.icon(key: const ValueKey('people-excel'), onPressed: list.isEmpty ? null : _excel, icon: const Icon(Icons.table_chart), label: const Text('Excel download')),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('people-search'),
          controller: search,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Name, email, account id, or kind (customer, vendor, staff...)', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (!loading) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('${list.length} people used the apps while signed in')),
        if (!loading)
          for (final p in list.take(200))
            Card(
              child: ExpansionTile(
                key: ValueKey('person-${p.uid}'),
                title: Text(_name(p.uid)),
                subtitle: Text('${who[p.uid]?['kind'] ?? 'account'} • ${p.total} actions on ${p.days.length} day${p.days.length == 1 ? '' : 's'}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final e in (p.counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) Chip(label: Text('${usageEventLabels[e.key] ?? e.key}: ${e.value}')),
                  ]),
                  const SizedBox(height: 6),
                  for (final k in (p.keys.values.toList()..sort((a, b) => b.count.compareTo(a.count))).take(30)) Text('${k.label} • ${k.count}'),
                ],
              ),
            ),
      ],
    );
  }
}
