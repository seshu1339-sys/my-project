import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'admin_frame.dart';
import 'report_abuse.dart' show reportReasons;

/// Admin > Reports: every shop, provider and customer that was reported, newest first. One that reached the admin's number
/// (Business Profile > Reports for an automatic temporary suspension, 10 by default) is suspended for now; the admin restores it or
/// blocks it for good (its email and phone then go on the Block list). Reads abuseTargets, abuseReports and adminAlerts
/// (functions/modules/abuse-reports).
class AdminReportsPage extends StatelessWidget {
  const AdminReportsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => AdminNeedsFirebase(store: store, child: _Reports(store: store));
}

class _Reports extends StatefulWidget {
  const _Reports({required this.store});
  final Store store;
  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  Store get store => widget.store;
  late final targets = store.firestore.collection('abuseTargets').orderBy('lastAt', descending: true).limit(200).snapshots();
  late final alerts = store.firestore.collection('adminAlerts').where('read', isEqualTo: false).limit(50).snapshots();
  String filter = 'all';
  bool busy = false;

  Future<void> _decide(String key, String action, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(action == 'block' ? 'Block $label for good?' : 'Restore $label?'),
        content: Text(action == 'block'
            ? 'The account stays suspended and its email and phone numbers go on the Block list: they cannot register or sign in again.'
            : 'The account works again and its listings show again. New reports start a new count.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(key: ValueKey('report-confirm-$action'), onPressed: () => Navigator.pop(dialog, true), child: Text(action == 'block' ? 'Block' : 'Restore')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await store.call('decideAbuseTarget', {'targetKey': key, 'action': action});
      messenger.showSnackBar(SnackBar(content: Text(action == 'block' ? '$label is blocked' : '$label is restored')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _alerts() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: alerts,
    builder: (context, snap) {
      final docs = snap.data?.docs ?? const [];
      if (docs.isEmpty) return const SizedBox.shrink();
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Column(children: [
          for (final d in docs)
            ListTile(
              leading: const Icon(Icons.notification_important_outlined),
              title: Text('${d.data()['label'] ?? ''} was suspended after ${d.data()['count'] ?? ''} reports'),
              subtitle: const Text('Look at the reports below: restore it or block it for good.'),
              trailing: TextButton(onPressed: () => d.reference.update({'read': true}), child: const Text('Seen')),
            ),
        ]),
      );
    },
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: targets,
    builder: (context, snap) {
      if (snap.hasError) return const Center(child: Text('Reports could not load.'));
      final all = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final shown = [for (final d in all) if (filter == 'all' || d.data()['state'] == filter || (filter == 'ok' && (d.data()['state'] ?? 'ok') == 'ok')) d];
      return ListView(padding: const EdgeInsets.all(12), children: [
        Text('Reports', style: Theme.of(context).textTheme.headlineSmall),
        const Text('Only people who really dealt with a shop, provider or customer can report them, once. At your number of reports '
            '(Business Profile) the account is suspended for now; you decide here. Who reported is never shown to the person reported.'),
        const SizedBox(height: 8),
        _alerts(),
        Wrap(spacing: 8, children: [
          for (final f in const {'all': 'All', 'suspended': 'Suspended (decide)', 'ok': 'Reported', 'restored': 'Restored', 'blocked': 'Blocked'}.entries)
            ChoiceChip(key: ValueKey('reports-filter-${f.key}'), label: Text(f.value), selected: filter == f.key, onSelected: (_) => setState(() => filter = f.key)),
        ]),
        const SizedBox(height: 8),
        if (shown.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No reports here.', key: ValueKey('reports-empty'))),
        for (final d in shown) _TargetCard(store: store, doc: d, busy: busy, onDecide: _decide),
      ]);
    },
  );
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.store, required this.doc, required this.busy, required this.onDecide});
  final Store store;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool busy;
  final Future<void> Function(String key, String action, String label) onDecide;

  @override
  Widget build(BuildContext context) {
    final t = doc.data();
    final label = '${t['label'] ?? doc.id}';
    final state = '${t['state'] ?? 'ok'}';
    final kind = '${t['kind'] ?? ''}';
    return Card(
      key: ValueKey('report-target-${doc.id}'),
      child: ExpansionTile(
        leading: Icon(state == 'suspended' ? Icons.pause_circle_outline : state == 'blocked' ? Icons.block : Icons.flag_outlined,
            color: state == 'suspended' || state == 'blocked' ? Theme.of(context).colorScheme.error : null),
        title: Text('$label • ${t['count'] ?? 0} reports'),
        subtitle: Text('${kind[0].toUpperCase()}${kind.substring(1)} • $state${t['countAtRestore'] is num && (t['countAtRestore'] as num) > 0 ? ' • ${t['countAtRestore']} before the last restore' : ''}'),
        children: [
          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: store.firestore.collection('abuseReports').where('targetKey', isEqualTo: doc.id).limit(100).get(),
            builder: (context, reports) => Column(children: [
              for (final r in reports.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                ListTile(
                  dense: true,
                  title: Text(reportReasons[r.data()['reason']] ?? '${r.data()['reason']}'),
                  subtitle: Text([
                    if ('${r.data()['details'] ?? ''}'.isNotEmpty) '${r.data()['details']}',
                    'by a ${r.data()['reporterRole'] == 'vendor' ? 'vendor' : 'customer'}',
                    if (r.data()['at'] is Timestamp) _date((r.data()['at'] as Timestamp).toDate()),
                  ].join(' • ')),
                ),
            ]),
          ),
          OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: [
            if (state == 'suspended' || state == 'blocked')
              OutlinedButton(key: ValueKey('report-restore-${doc.id}'), onPressed: busy ? null : () => onDecide(doc.id, 'restore', label), child: const Text('Restore')),
            if (state != 'blocked')
              FilledButton(key: ValueKey('report-block-${doc.id}'), onPressed: busy ? null : () => onDecide(doc.id, 'block', label), child: const Text('Block for good')),
          ]),
        ],
      ),
    );
  }
}

String _date(DateTime t) => '${t.day}/${t.month}/${t.year}';

/// Admin > Block list: the emails and phone numbers that cannot register or sign in again (functions/block-list.js). Blocking a
/// reported account adds its contacts here; the admin can also add or remove one by hand.
class AdminBlockListPage extends StatelessWidget {
  const AdminBlockListPage({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => AdminNeedsFirebase(store: store, child: _BlockList(store: store));
}

class _BlockList extends StatefulWidget {
  const _BlockList({required this.store});
  final Store store;
  @override
  State<_BlockList> createState() => _BlockListState();
}

class _BlockListState extends State<_BlockList> {
  late final list = widget.store.firestore.collection('blockedContacts').limit(500).snapshots();
  final value = TextEditingController();

  @override
  void dispose() {
    value.dispose();
    super.dispose();
  }

  Future<void> _run(String name, Map<String, dynamic> data, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.store.call(name, data);
      messenger.showSnackBar(SnackBar(content: Text(done)));
      value.clear();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
    Text('Block list', style: Theme.of(context).textTheme.headlineSmall),
    const Text('These emails and phone numbers cannot register again or sign in to any app. Only you add them (Reports > Block for good, or here).'),
    Row(children: [
      Expanded(child: TextField(key: const ValueKey('block-value'), controller: value, decoration: const InputDecoration(labelText: 'Email or 10-digit phone'))),
      const SizedBox(width: 8),
      FilledButton(
        key: const ValueKey('block-add'),
        onPressed: () {
          final v = value.text.trim();
          _run('blockContact', v.contains('@') ? {'email': v} : {'phone': v}, '$v is blocked');
        },
        child: const Text('Block'),
      ),
    ]),
    const SizedBox(height: 8),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: list,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (docs.isEmpty) return const Text('Nobody is blocked.', key: ValueKey('block-empty'));
        return Column(children: [
          for (final d in docs)
            ListTile(
              title: Text('${d.data()['value'] ?? d.id}'),
              subtitle: Text('${d.data()['kind'] ?? ''}${'${d.data()['reason'] ?? ''}'.isEmpty ? '' : ' • ${d.data()['reason']}'}'),
              trailing: TextButton(onPressed: () => _run('unblockContact', {'key': d.id}, '${d.data()['value'] ?? d.id} can register again'), child: const Text('Remove')),
            ),
        ]);
      },
    ),
  ]);
}
