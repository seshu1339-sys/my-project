import 'package:flutter/material.dart';

import '../data/store.dart';
import 'shared.dart';

/// Settings > Sample data: how many sample records there are (marked isSample, or belonging to a sample account) and the one button that
/// deletes them all, with their photos and the sample accounts (functions/samples.js). Real records are never touched.
class AdminSamplesPage extends StatefulWidget {
  const AdminSamplesPage({super.key, required this.store, this.call});
  final Store store;
  // How requests reach the server; replaced in tests.
  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)? call;
  @override
  State<AdminSamplesPage> createState() => _AdminSamplesPageState();
}

class _AdminSamplesPageState extends State<AdminSamplesPage> {
  Map<String, dynamic>? summary, result;
  String? error;
  bool busy = false;

  Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic> data = const {}]) => (widget.call ?? widget.store.call)(name, data);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final s = await _call('sampleSummary');
      if (mounted) setState(() => summary = s);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  int _n(String key) => (summary?[key] as num?)?.toInt() ?? 0;

  Future<void> _delete() async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Delete all samples?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This deletes ${_n('total')} sample record(s), their photos, ${_n('accounts')} sample account(s) and the sample photos in '
                '${_n('rightBoxes')} Right Side Ad Box(es). Real records are not touched. This cannot be undone.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('samples-confirm-text'),
                controller: typed,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
                onChanged: (_) => setDialog(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              key: const ValueKey('samples-confirm-delete'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: typed.text.trim() == 'DELETE' ? () => Navigator.pop(context, true) : null,
              child: const Text('Delete all samples'),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      final r = await _call('deleteAllSamples', {'confirm': 'DELETE'});
      if (!mounted) return;
      setState(() => result = r);
      message(context, 'Deleted ${r['records']} sample record(s), ${r['photos']} photo(s) and ${r['accounts']} account(s).');
      await _load();
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final by = Map<String, dynamic>.from(summary?['byCollection'] as Map? ?? const {});
    final rows = by.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final nothing = summary != null && _n('total') == 0 && _n('rightBoxes') == 0;
    return ListView(
      key: const ValueKey('admin-samples'),
      padding: const EdgeInsets.all(20),
      children: [
        Text('Sample data', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
          'Sample records carry an orange SAMPLE label everywhere in the admin panel. They are made by the sample script, or by a '
          'sample account through the apps. When you are ready to add your real data, delete them all here in one go.',
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text('Could not count the samples: $error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (summary != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_n('total')} sample records • ${_n('accounts')} sample accounts • ${_n('rightBoxes')} boxes with a sample photo',
                    key: const ValueKey('samples-total'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  for (final r in rows) Text('${r.key}: ${r.value}'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(key: const ValueKey('samples-refresh'), onPressed: busy ? null : _load, icon: const Icon(Icons.refresh), label: const Text('Count again')),
            FilledButton.icon(
              key: const ValueKey('samples-delete-all'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: busy || nothing ? null : _delete,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Delete all samples'),
            ),
          ],
        ),
        if (result != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Last deletion: ${result!['records']} records, ${result!['photos']} photos, ${result!['accounts']} accounts, ${result!['rightBoxes']} boxes.',
              key: const ValueKey('samples-result'),
            ),
          ),
      ],
    );
  }
}
