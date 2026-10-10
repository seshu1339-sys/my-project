import 'package:flutter/material.dart';

import '../data/store.dart';

/// Read-only monitoring dashboard: lists backup jobs and lets the admin
/// trigger one on demand or fetch rollback instructions. Health-check email
/// alerts themselves are sent by the scheduled functions/ai-agent-monitoring.js
/// job — this widget only displays state, it never writes business data.
/// Rollback is deliberately instructions-only: getRollbackInstructions
/// returns a `gcloud firestore import` command for a human to run themselves,
/// never an automated restore.
class AiAgentMonitoring extends StatefulWidget {
  const AiAgentMonitoring({super.key, required this.store});
  final Store store;
  @override
  State<AiAgentMonitoring> createState() => _AiAgentMonitoringState();
}

class _AiAgentMonitoringState extends State<AiAgentMonitoring> {
  List<dynamic> backups = [];
  bool loading = true;
  bool backingUp = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final result = await widget.store.call('listBackups', const {});
      setState(() => backups = (result['backups'] as List?) ?? const []);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _backupNow() async {
    setState(() => backingUp = true);
    try {
      await widget.store.call('requestBackupNow', const {});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => backingUp = false);
  }

  Future<void> _showRollbackInstructions(String jobId) async {
    try {
      final result = await widget.store.call('getRollbackInstructions', {'jobId': jobId});
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
        title: const Text('Rollback instructions'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${result['warning']}'),
          const SizedBox(height: 12),
          SelectableText('${result['command']}'),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Close'))],
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(padding: const EdgeInsets.all(16), children: [
      FilledButton.icon(
        onPressed: backingUp ? null : _backupNow,
        icon: backingUp ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.backup),
        label: const Text('Backup now'),
      ),
      const SizedBox(height: 16),
      const Text('Recent backups', style: TextStyle(fontWeight: FontWeight.bold)),
      if (loading) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator())),
      if (!loading && backups.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No backups yet.')),
      for (final b in backups)
        Card(child: ListTile(
          title: Text('${b['gcsPath']}'),
          subtitle: Text('Status: ${b['status']}'),
          trailing: TextButton(onPressed: () => _showRollbackInstructions(b['id'] as String), child: const Text('Rollback instructions')),
        )),
    ]),
  );
}
