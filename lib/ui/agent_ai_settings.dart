import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/agent_log.dart';

/// This month's AI use (owner spec C): calls and tokens from aiCallLog (every AI call of every feature is logged there by ai-core).
class AiMonthUsage {
  const AiMonthUsage(this.calls, this.inputTokens, this.outputTokens);
  final int calls, inputTokens, outputTokens;
}

/// The first moment of this month in India, as UTC.
DateTime istMonthStart(DateTime nowUtc) {
  final ist = nowUtc.toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime.utc(ist.year, ist.month).subtract(const Duration(hours: 5, minutes: 30));
}

Future<AiMonthUsage> loadAiMonthUsage(Store store, {DateTime? now}) async {
  final from = Timestamp.fromDate(istMonthStart(now ?? DateTime.now().toUtc()));
  final r = await store.firestore
      .collection('aiCallLog')
      .where('at', isGreaterThanOrEqualTo: from)
      .aggregate(count(), sum('inputTokens'), sum('outputTokens'))
      .get();
  return AiMonthUsage(r.count ?? 0, (r.getSum('inputTokens') ?? 0).round(), (r.getSum('outputTokens') ?? 0).round());
}

/// The agent's own switches, in settings/agent (public like every settings record, so nothing secret is kept here):
///   aiExplain  'true' = for each failure the AI explains it in Telugu with a fix and a Claude Code prompt (owner spec H); off = only
///              the red mark and the raw error, zero AI cost. Off until the admin turns it on.
const agentSettingsId = 'agent';

bool aiExplainOn(Store store) => store.entries('settings').where((e) => e.id == agentSettingsId).firstOrNull?.text('aiExplain') == 'true';

/// Settings > AI provider & usage: the provider, the API key (saved on the server only; this page never sees it again, only its last
/// 4 letters), this month's AI use, and the "AI explain" switch.
class AgentAiSettingsPage extends StatefulWidget {
  const AgentAiSettingsPage({super.key, required this.store, this.status, this.saveKey, this.usage});
  final Store store;

  /// Test seams: the server calls aiKeyStatus / setAiKey and the month's use.
  final Future<Map<String, dynamic>> Function()? status;
  final Future<Map<String, dynamic>> Function(String provider, String key)? saveKey;
  final Future<AiMonthUsage> Function()? usage;

  @override
  State<AgentAiSettingsPage> createState() => _AgentAiSettingsPageState();
}

class _AgentAiSettingsPageState extends State<AgentAiSettingsPage> {
  final key = TextEditingController();
  String provider = 'anthropic';
  Map<String, dynamic>? keyState;
  AiMonthUsage? use;
  String? error, saved;
  bool busy = false;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    key.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await (widget.status ?? () => store.call('aiKeyStatus', {}))();
      if (mounted) setState(() { keyState = s; provider = '${s['provider'] ?? 'anthropic'}'; });
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    }
    try {
      final u = await (widget.usage ?? () => loadAiMonthUsage(store))();
      if (mounted) setState(() => use = u);
    } catch (_) {/* the counter shows "—" */}
  }

  String _clean(Object e) => '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '').replaceFirst('Bad state: ', '');

  Future<void> _save({bool clear = false}) async {
    setState(() { busy = true; error = null; saved = null; });
    try {
      final s = await (widget.saveKey ?? (p, k) => store.call('setAiKey', {'provider': p, 'key': k}))(provider, clear ? '' : key.text.trim());
      key.clear();
      if (mounted) setState(() { keyState = s; saved = clear ? 'Key removed. AI is off (the free local search still works).' : 'Saved on the server.'; });
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _explain(bool on) async {
    final record = store.entries('settings').where((e) => e.id == agentSettingsId).firstOrNull ?? const Entry(agentSettingsId, {'name': 'Agent'});
    await store.save('settings', Entry(agentSettingsId, {...record.data, 'aiExplain': on ? 'true' : 'false'}));
    AgentLog.write(store, action: 'ai_explain', target: on ? 'on' : 'off');
    if (mounted) setState(() {});
  }

  String _n(int n) => n >= 1000000 ? '${(n / 1000000).toStringAsFixed(1)} M' : n >= 1000 ? '${(n / 1000).toStringAsFixed(1)} K' : '$n';

  @override
  Widget build(BuildContext context) {
    final s = keyState;
    final source = '${s?['source'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('AI is used only when the free local search finds nothing, when you press "Ask AI", and (if you turn it on) to explain failures. The key stays on the server: no app can read it.'),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('AI provider and key', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                key: const ValueKey('ai-key-status'),
                s == null
                    ? 'Checking…'
                    : s['set'] == true
                    ? (source == 'admin' ? 'Key set here (…${s['last4']}).' : 'Key set in the server secret.')
                    : 'No key: AI is off. The local search, counts and health checks still work.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('ai-provider'),
                initialValue: provider,
                decoration: const InputDecoration(labelText: 'Provider', border: OutlineInputBorder(), isDense: true),
                items: const [DropdownMenuItem(value: 'anthropic', child: Text('Anthropic (Claude)'))],
                onChanged: (v) => setState(() => provider = v ?? 'anthropic'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('ai-key-input'),
                controller: key,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New API key (sk-ant-…)', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 12, children: [
                FilledButton(key: const ValueKey('ai-key-save'), onPressed: busy ? null : () => _save(), child: Text(busy ? 'Saving…' : 'Save key')),
                if (source == 'admin') OutlinedButton(key: const ValueKey('ai-key-clear'), onPressed: busy ? null : () => _save(clear: true), child: const Text('Remove key')),
              ]),
              if (saved != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(saved!, style: const TextStyle(color: Colors.green))),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, key: const ValueKey('ai-key-error'), style: const TextStyle(color: Colors.red))),
            ]),
          ),
        ),
        Card(
          child: ListTile(
            key: const ValueKey('ai-month-usage'),
            leading: const Icon(Icons.speed),
            title: const Text('AI use this month'),
            subtitle: Text(use == null ? '—' : '${use!.calls} AI calls · ${_n(use!.inputTokens)} tokens in · ${_n(use!.outputTokens)} tokens out'),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => Card(
            child: SwitchListTile(
              key: const ValueKey('ai-explain-switch'),
              value: aiExplainOn(store),
              onChanged: _explain,
              title: const Text('AI explain (failures)'),
              subtitle: const Text('ON: for each failure the AI explains the reason in Telugu, how to fix it, and gives a ready Claude Code prompt. OFF: only the red mark and the raw error (no AI cost).'),
            ),
          ),
        ),
      ],
    );
  }
}
