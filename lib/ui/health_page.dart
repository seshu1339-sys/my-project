import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../domain/health_status.dart';
import '../services/agent_log.dart';
import '../services/health_watch.dart';
import 'agent_ai_settings.dart';
import 'agent_hooks.dart';
import 'app_health_page.dart';
import 'health_extras.dart';

/// Business > Health (owner spec F + H, 17 Nov 2026): the daily self-test of the website and the admin panel (05:20 India time, or
/// "Run now"), the server's errors of the last 24 hours, and a link to App Health. A failing check is red with its raw error; with
/// "AI explain" ON it also gets the reason in Telugu, how to fix it and a ready Claude Code prompt (off: no AI cost at all).
class HealthPage extends StatefulWidget {
  const HealthPage({super.key, required this.store, this.runNow, this.explain, this.status});
  final Store store;

  /// Test seams: the server calls and a fixed status.
  final Future<Map<String, dynamic>> Function()? runNow;
  final Future<String> Function(HealthCheck check)? explain;
  final HealthStatus? status;

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  bool running = false;
  String? note;
  final explained = <String, String>{};
  final explaining = <String>{};

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    HealthWatch.instance.start(store);
  }

  Future<void> _run() async {
    setState(() { running = true; note = null; });
    try {
      final r = await (widget.runNow ?? () => store.call('runHealthCheckNow', {}))();
      if (mounted) setState(() => note = r['ok'] == true ? 'All checks passed.' : '${r['failed']} checks failed.');
    } catch (e) {
      if (mounted) setState(() => note = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
    if (mounted) setState(() => running = false);
  }

  Future<void> _explain(HealthCheck c) async {
    setState(() => explaining.add(c.id));
    try {
      final text = await (widget.explain ??
          (c) async => '${(await store.call('explainHealthProblem', {'key': 'check_${c.id}', 'title': c.name, 'error': c.error, 'where': c.group}))['text'] ?? ''}')(c);
      AgentLog.write(store, action: 'health_explain', target: c.id);
      if (mounted) setState(() => explained[c.id] = text);
    } catch (e) {
      if (mounted) setState(() => explained[c.id] = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
    if (mounted) setState(() => explaining.remove(c.id));
  }

  void _openAppHealth(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: const Text('App Health')), body: AppHealthPage(store: store))));

  String _when(DateTime? t) {
    if (t == null) return '';
    final l = t.toLocal();
    return '${l.day}/${l.month} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Widget _check(HealthCheck c, bool aiOn) {
    final registryId = c.registryIds.firstOrNull;
    final registryName = registryId == null ? '' : agentOptionName?.call(registryId) ?? '';
    final text = explained[c.id] ?? c.explain;
    return Card(
      key: ValueKey('health-check-${c.id}'),
      color: c.ok ? null : const Color(0xFFFFEBEE),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(c.ok ? Icons.check_circle : Icons.error, color: c.ok ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${c.ms} ms', style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
          if (!c.ok) ...[
            const SizedBox(height: 6),
            SelectableText(c.error, key: ValueKey('health-error-${c.id}'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            if (c.since != null) Text('Failing since ${_when(c.since)}', style: const TextStyle(fontSize: 12, color: Colors.red)),
            Wrap(spacing: 8, children: [
              if (registryId != null && agentOpenById != null)
                TextButton.icon(onPressed: () => agentOpenById!(context, store, registryId, command: 'health'), icon: const Icon(Icons.open_in_new, size: 16), label: Text('Open ${registryName.isEmpty ? 'the option' : registryName}')),
              if (aiOn && text.isEmpty)
                TextButton.icon(key: ValueKey('health-explain-${c.id}'), onPressed: explaining.contains(c.id) ? null : () => _explain(c), icon: const Icon(Icons.auto_awesome_outlined, size: 16), label: Text(explaining.contains(c.id) ? 'Explaining…' : 'AI explain (Telugu)')),
            ]),
            if (aiOn && text.isNotEmpty) _ExplainBox(text: text),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([HealthWatch.instance, store]),
    builder: (context, _) {
      final s = widget.status ?? HealthWatch.instance.status;
      // Server errors with the most first (owner spec part 1: most errors first).
      final serverErrors = [...s.serverErrors]..sort((a, b) => b.count.compareTo(a.count));
      final aiOn = aiExplainOn(store);
      final groups = <String, List<HealthCheck>>{};
      for (final c in s.checks) {
        groups.putIfAbsent(c.group, () => []).add(c);
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Icon(s.failing.isEmpty ? Icons.verified_outlined : Icons.report_gmailerrorred, color: s.failing.isEmpty ? Colors.green : Colors.red, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                key: const ValueKey('health-summary'),
                !s.ran
                    ? 'The daily check has not run yet.'
                    : s.failing.isEmpty
                    ? 'All ${s.checks.length} checks passed (${_when(s.at)}).'
                    : '${s.failing.length} of ${s.checks.length} checks failing (${_when(s.at)}).',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(key: const ValueKey('health-run-now'), onPressed: running ? null : _run, icon: const Icon(Icons.play_arrow), label: Text(running ? 'Running…' : 'Run now')),
          ]),
          const SizedBox(height: 4),
          Text(
            'Every day at 05:20 (India): each page opens, the server functions answer, a test record and a test photo save and are deleted '
            '(real data is never touched), ad data, radius ads and the Android remote config. No AI. '
            '${aiOn ? 'AI explain is ON: failures get a Telugu explanation and a Claude Code prompt.' : 'AI explain is OFF (Settings > AI provider & usage): only the red mark and the raw error.'}',
            style: const TextStyle(fontSize: 12),
          ),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note!, key: const ValueKey('health-note'))),
          const SizedBox(height: 12),
          // AI Agent + Health System part 1: push alerts, the biggest problems of every app (most affected first) and the limits.
          if (widget.status == null) ...[
            HealthAlertsSwitch(store: store),
            TopProblemsCard(store: store, openAppHealth: () => _openAppHealth(context)),
            SpentThisMonthCard(store: store),
          ],
          for (final g in groups.entries) ...[
            Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 4), child: Text(g.key, style: Theme.of(context).textTheme.titleSmall)),
            for (final c in g.value) _check(c, aiOn),
          ],
          Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 4), child: Text('Server errors (last 24 hours)', style: Theme.of(context).textTheme.titleSmall)),
          if (s.serverErrorsNote.isNotEmpty) Text(s.serverErrorsNote, style: const TextStyle(color: Colors.orange)),
          if (s.serverErrors.isEmpty && s.serverErrorsNote.isEmpty) const Text('No server errors.', key: ValueKey('health-no-server-errors')),
          for (final e in serverErrors)
            ListTile(
              dense: true,
              leading: const Icon(Icons.dns_outlined, color: Colors.red),
              title: Text('${e.service}: ${e.message}'),
              subtitle: Text('${e.count} times · last ${e.last.replaceFirst('T', ' ').split('.').first}'),
              trailing: aiOn
                  ? IconButton(
                      tooltip: 'AI explain',
                      icon: const Icon(Icons.auto_awesome_outlined),
                      onPressed: () => _explain(HealthCheck(id: 'server_${e.service}', name: 'Server function ${e.service}', group: 'Server errors', ok: false, error: e.message)),
                    )
                  : null,
            ),
          for (final e in s.serverErrors)
            if (explained['server_${e.service}'] != null) _ExplainBox(text: explained['server_${e.service}']!),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              key: const ValueKey('health-open-app-health'),
              leading: const Icon(Icons.phone_android),
              title: const Text('App Health: what goes wrong for real people'),
              subtitle: Text('Vendor, Staff and User apps, the website and the admin panel${HealthWatch.instance.newReports > 0 ? ' · ${HealthWatch.instance.newReports} new reports' : ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openAppHealth(context),
            ),
          ),
          if (widget.status == null) HealthLimitsCard(store: store),
        ],
      );
    },
  );
}

/// An AI explanation: the Telugu reason and fix, with a "Copy" for the Claude Code prompt in it.
class _ExplainBox extends StatelessWidget {
  const _ExplainBox({required this.text});
  final String text;

  String get _prompt {
    final m = RegExp(r'```(?:\w+)?\n([\s\S]*?)```').firstMatch(text);
    return (m?.group(1) ?? text).trim();
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('health-explain-text'),
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // The Claude Code prompt shows as a block of its own, without the ``` marks.
      SelectableText(text.replaceAll(RegExp(r'```\w*\n?'), '').trim()),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _prompt));
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Claude Code prompt copied')));
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy Claude Code prompt'),
        ),
      ),
    ]),
  );
}

/// The command box's "what is not working?" (owner spec H): the failing checks, server errors and the apps' problems of the last day.
Future<String> answerNotWorking(Store store) async {
  HealthWatch.instance.start(store);
  var status = HealthWatch.instance.status;
  var problems = <AppProblem>[];
  var reports = HealthWatch.instance.newReports;
  if (store.live) {
    final db = store.firestore;
    status = HealthStatus.from((await db.collection('healthStatus').doc('current').get()).data());
    final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1)));
    final q = await db.collection('appProblems').where('lastAt', isGreaterThan: since).limit(300).get();
    problems = [for (final d in q.docs) AppProblem.from(d.id, d.data())];
    reports = (await db.collection('problemReports').where('status', isEqualTo: 'new').count().get()).count ?? 0;
  }
  return notWorkingAnswer(status, recentProblems: problems, newReports: reports);
}
