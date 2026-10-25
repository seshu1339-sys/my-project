import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/shop_ads.dart';
import '../services/file_download.dart';
import '../services/report_export.dart';
import 'text_prompt_dialog.dart';

/// The automatic sweep's settings (settings/inactiveAccounts, functions/inactive-accounts.js), off unless switched on.
class InactiveSettings {
  const InactiveSettings(this.entry);
  final Entry entry;
  bool get autoDisable => entry.data['autoDisable'] == true;
  bool get autoDelete => entry.data['autoDelete'] == true;
  int get disableAfterDays => entry.number('disableAfterDays', 30).round();
  int get deleteAfterDays => entry.number('deleteAfterDays', 90).round();
}

/// Admin > Insights > Analytics > Inactive accounts: who has not used any app for 7, 30 or 90 days, with Disable / Enable and
/// Delete (customers only; typing DELETE confirms), an Excel download, and the automatic daily sweep, which does nothing until
/// the admin switches it on.
class InactiveAccountsView extends StatefulWidget {
  const InactiveAccountsView({super.key, required this.store, this.load});
  final Store store;
  // Test seam: the inactive accounts for a number of days.
  final Future<List<Map<String, dynamic>>> Function(int days)? load;
  @override
  State<InactiveAccountsView> createState() => _InactiveAccountsViewState();
}

class _InactiveAccountsViewState extends State<InactiveAccountsView> {
  int days = 30;
  List<Map<String, dynamic>> accounts = const [];
  bool loading = true, busy = false;
  String? error;
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void toast(Object m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$m')));

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = widget.load != null
          ? await widget.load!(days)
          : [for (final r in ((await store.call('inactiveAccounts', {'days': days}))['accounts'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
      if (mounted) setState(() => accounts = rows);
    } catch (e) {
      if (mounted) setState(() => error = 'The list could not load: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _disable(Map<String, dynamic> a, bool disabled) async {
    setState(() => busy = true);
    try {
      await store.call('setAccountDisabled', {'uid': a['uid'], 'disabled': disabled});
      setState(() => a['disabled'] = disabled);
      toast(disabled ? 'Disabled: ${a['email']} cannot sign in.' : 'Enabled: ${a['email']} can sign in again.');
    } catch (e) {
      toast(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final typed = await askText(
      context,
      title: 'Delete ${a['email'] ?? a['uid']}?',
      label: 'Type DELETE to confirm',
      helper: 'The account and its personal data are deleted for good. Its orders are kept.',
      confirm: 'Delete',
      fieldKey: ValueKey('delete-confirm-${a['uid']}'),
    );
    if (typed == null || !mounted) return;
    if (typed != 'DELETE') return toast('Not deleted: type DELETE to confirm.');
    setState(() => busy = true);
    try {
      await store.call('deleteInactiveAccount', {'uid': a['uid'], 'confirm': 'DELETE'});
      setState(() => accounts = [for (final x in accounts) if (x['uid'] != a['uid']) x]);
      toast('Deleted.');
    } catch (e) {
      toast(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _setting(Map<String, dynamic> changes) async {
    try {
      await store.updateFields('settings', 'inactiveAccounts', changes, fallback: Entry('inactiveAccounts', {..._settings.entry.data, ...changes}));
    } catch (e) {
      toast(e);
    }
  }

  Future<void> _days(String field, int current, String title) async {
    final text = await askText(context, title: title, label: 'Days', initial: '$current', keyboardType: TextInputType.number, fieldKey: ValueKey('inactive-$field'));
    final n = int.tryParse(text ?? '');
    if (n == null || n < 7 || n > 3650) return;
    await _setting({field: n});
  }

  InactiveSettings get _settings => InactiveSettings(store.entries('settings').where((e) => e.id == 'inactiveAccounts').firstOrNull ?? const Entry('inactiveAccounts', {}));

  Future<void> _excel() async {
    final table = ReportTable('Inactive for $days days or more', ['Email', 'Name', 'Kind', 'Last active', 'Days inactive', 'Disabled'], [
      for (final a in accounts) ['${a['email'] ?? ''}', '${a['name'] ?? ''}', '${a['kind'] ?? ''}', _date(a['lastActiveAt']), a['inactiveDays'] ?? 0, a['disabled'] == true ? 'yes' : 'no'],
    ]);
    try {
      await downloadFile('inactive-$days-days.xlsx', buildXlsx([table]), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } catch (e) {
      toast('Could not download: $e');
    }
  }

  String _date(Object? millis) => millis is num ? shopAdDate(DateTime.fromMillisecondsSinceEpoch(millis.round())) : '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final s = _settings;
      return ListView(
        key: const ValueKey('inactive-accounts'),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Automatic (every night)', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('Only customer accounts. A deleted account cannot be brought back. Both are off until you switch them on.'),
                SwitchListTile(
                  key: const ValueKey('inactive-auto-disable'),
                  value: s.autoDisable,
                  onChanged: (v) => _setting({'autoDisable': v}),
                  title: Text('Disable customers inactive for ${s.disableAfterDays} days'),
                  subtitle: const Text('They cannot sign in until you enable them again.'),
                  secondary: TextButton(onPressed: () => _days('disableAfterDays', s.disableAfterDays, 'Disable after how many days?'), child: const Text('Days')),
                ),
                SwitchListTile(
                  key: const ValueKey('inactive-auto-delete'),
                  value: s.autoDelete,
                  onChanged: (v) => _setting({'autoDelete': v}),
                  title: Text('Delete customers disabled for inactivity after ${s.deleteAfterDays} days'),
                  subtitle: const Text('Their account and personal data are deleted for good; orders are kept.'),
                  secondary: TextButton(onPressed: () => _days('deleteAfterDays', s.deleteAfterDays, 'Delete after how many days?'), child: const Text('Days')),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
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
              OutlinedButton.icon(key: const ValueKey('inactive-excel'), onPressed: accounts.isEmpty ? null : _excel, icon: const Icon(Icons.table_chart), label: const Text('Excel download')),
            ],
          ),
          if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (!loading) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('${accounts.length} account${accounts.length == 1 ? '' : 's'} not used for $days days or more', key: const ValueKey('inactive-count'))),
          if (!loading)
            for (final a in accounts)
              Card(
                key: ValueKey('inactive-${a['uid']}'),
                child: ListTile(
                  title: Text('${a['email'] ?? ''}'.isEmpty ? '${a['uid']}' : '${a['email']}'),
                  subtitle: Text('${a['kind'] ?? ''} • last active ${_date(a['lastActiveAt'])} (${a['inactiveDays'] ?? '?'} days)${a['disabled'] == true ? ' • disabled' : ''}'),
                  trailing: Wrap(spacing: 4, children: [
                    TextButton(
                      key: ValueKey('inactive-toggle-${a['uid']}'),
                      onPressed: busy ? null : () => _disable(a, a['disabled'] != true),
                      child: Text(a['disabled'] == true ? 'Enable' : 'Disable'),
                    ),
                    if (a['kind'] == 'customer')
                      TextButton(key: ValueKey('inactive-delete-${a['uid']}'), onPressed: busy ? null : () => _delete(a), child: const Text('Delete')),
                  ]),
                ),
              ),
        ],
      );
    },
  );
}
