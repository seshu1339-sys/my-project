import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/fix_texts.dart';
import '../domain/health_status.dart';
import '../services/agent_log.dart';
import 'admin_frame.dart';
import 'agent_ai_settings.dart';

/// The admin's AI Agent (AI Agent + Health System part 4, 17 Nov 2026). It opens with a summary: the open problems of every app with
/// the MOST AFFECTED PEOPLE first (app, screen / option, how many people, how many times, phone models, main cause, the reports waiting
/// for a reply and the automatic screenshot), each with a Telugu explanation and the fix it proposes. Then it asks "Fix this?":
///   * Fix: a fix request goes to the fix agent (Claude Code on the owner's PC, tools/fix-queue). It writes the code fix, runs the
///     tests and shows the exact changes here. NOTHING goes live by itself: only after the admin presses OK.
///   * Don't fix (or the fix did not work): a box for what to do next; the agent follows it and asks again.
///   * After OK: website / admin / server fixes deploy at once; design / remote-config fixes apply to the apps at once; app code fixes
///     become a new build on the Closed testing track (Google review). Every fix has a backup and one-click Undo; who approved, when and
///     what changed is logged. When a fix is live, the problem's reports become Solved and each person is told in their language.
class FixAgentPage extends StatelessWidget {
  const FixAgentPage({super.key, required this.store, this.data});
  final Store store;

  /// Test seam: everything the page reads, instead of Firestore.
  final FixAgentData? data;

  @override
  Widget build(BuildContext context) => data != null ? _FixAgent(store: store, data: data!) : AdminNeedsFirebase(store: store, child: _FixAgent(store: store, data: FixAgentData.live(store)));
}

/// What the AI Agent reads and writes (Firestore in the panel; fakes in the tests).
class FixAgentData {
  FixAgentData({required this.problems, required this.waitingByProblem, required this.requests, required this.agentSeen, required this.ask, required this.decide, this.shot});

  final Future<List<AppProblem>> Function() problems;
  final Future<Map<String, int>> Function() waitingByProblem;

  /// The fix requests, newest first (live).
  final Stream<List<Map<String, dynamic>>> Function() requests;

  /// When the fix agent on the PC last checked the queue (null: never).
  final Stream<DateTime?> Function() agentSeen;

  /// A new fix request for a problem: {problemId, title, explanation, instruction, …}.
  final Future<void> Function(Map<String, dynamic> request) ask;

  /// The admin's decision on a request: OK, Don't fix with what to do next, Undo.
  final Future<void> Function(String id, Map<String, dynamic> changes) decide;

  final Future<String?> Function(String caseId)? shot;

  factory FixAgentData.live(Store store) {
    final db = store.firestore;
    String uid() => FirebaseAuth.instance.currentUser?.uid ?? '';
    return FixAgentData(
      problems: () async {
        final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 14)));
        final q = await db.collection('appProblems').where('lastAt', isGreaterThan: since).limit(400).get();
        return mostAffectedFirst([for (final d in q.docs) AppProblem.from(d.id, d.data())].where((p) => p.side != 'user' && !p.solved).toList());
      },
      waitingByProblem: () async {
        final q = await db.collection('supportTickets').where('status', isEqualTo: 'sent').limit(500).get();
        final out = <String, int>{};
        for (final d in q.docs) {
          final p = '${d.data()['problemId'] ?? ''}';
          out[p] = (out[p] ?? 0) + 1;
        }
        return out;
      },
      requests: () => db.collection('fixRequests').orderBy('at', descending: true).limit(100).snapshots().map((q) => [for (final d in q.docs) {'id': d.id, ...d.data()}]),
      agentSeen: () => db.collection('fixAgent').doc('status').snapshots().map((d) => (d.data()?['seenAt'] as Timestamp?)?.toDate()),
      ask: (r) async {
        await db.collection('fixRequests').add({...r, 'status': r['status'] == 'declined' ? 'declined' : 'requested', 'by': uid(), 'at': FieldValue.serverTimestamp()});
      },
      // Who decided and when; an OK also records who approved it (the rules allow OK only on a ready fix, by this admin).
      decide: (id, changes) => db.collection('fixRequests').doc(id).update({
        ...changes,
        if (changes['status'] == 'approved') ...{'approvedBy': uid(), 'approvedAt': FieldValue.serverTimestamp()},
        'decidedBy': uid(),
        'decidedAt': FieldValue.serverTimestamp(),
      }),
      shot: (caseId) async => '${(await db.collection('appShots').doc(caseId).get()).data()?['data'] ?? ''}',
    );
  }
}

class _FixAgent extends StatefulWidget {
  const _FixAgent({required this.store, required this.data});
  final Store store;
  final FixAgentData data;
  @override
  State<_FixAgent> createState() => _FixAgentState();
}

class _FixAgentState extends State<_FixAgent> {
  late Future<(List<AppProblem>, Map<String, int>)> loaded = _load();
  StreamSubscription<List<Map<String, dynamic>>>? _req;
  StreamSubscription<DateTime?>? _seen;
  List<Map<String, dynamic>> requests = const [];
  DateTime? agentSeen;
  final instructions = <String, TextEditingController>{};
  final askingWhy = <String>{};
  final shots = <String, String>{};
  final explained = <String, String>{};

  Future<(List<AppProblem>, Map<String, int>)> _load() async => (await widget.data.problems(), await widget.data.waitingByProblem());

  @override
  void initState() {
    super.initState();
    _req = widget.data.requests().listen((r) => setState(() => requests = r), onError: (_) {});
    _seen = widget.data.agentSeen().listen((t) => setState(() => agentSeen = t), onError: (_) {});
  }

  @override
  void dispose() {
    _req?.cancel();
    _seen?.cancel();
    for (final c in instructions.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _box(String key) => instructions.putIfAbsent(key, TextEditingController.new);

  /// The newest fix request of a problem (null when none).
  Map<String, dynamic>? _requestOf(String problemId) => requests.where((r) => r['problemId'] == problemId).firstOrNull;

  String _title(AppProblem p) {
    final app = [for (final t in appHealthTabs) if (t.$1 == p.app && t.$2 == p.platform) t.$3].firstOrNull ?? p.app;
    return '$app · ${p.screen.isEmpty ? (problemKindNames[p.kind] ?? p.kind) : p.screen}${p.option.isEmpty ? '' : ' · "${p.option}"'}';
  }

  Future<void> _fix(AppProblem p, {String instruction = ''}) async {
    final t = fixTextOf(side: p.side, cause: p.cause);
    await widget.data.ask({
      'problemId': p.id, 'title': _title(p), 'app': p.app, 'platform': p.platform, 'kind': p.kind, 'message': p.message, 'screen': p.screen,
      'option': p.option, 'side': p.side, 'cause': p.cause, 'users': p.users, 'count': p.count, 'devices': p.devices, 'version': p.version,
      'explanation': t.reason, 'proposedFix': t.fix, 'instruction': instruction,
    });
    AgentLog.write(widget.store, action: 'fix_requested', target: p.id, details: {'instruction': instruction});
    setState(() => askingWhy.remove(p.id));
  }

  Future<void> _decline(AppProblem p) async {
    final text = _box('p:${p.id}').text.trim();
    if (text.isEmpty) {
      AgentLog.write(widget.store, action: 'fix_declined', target: p.id);
      await widget.data.ask({'problemId': p.id, 'title': _title(p), 'app': p.app, 'platform': p.platform, 'kind': p.kind, 'message': p.message, 'status': 'declined'});
      setState(() => askingWhy.remove(p.id));
      return;
    }
    _box('p:${p.id}').clear();
    await _fix(p, instruction: text);
  }

  Future<void> _ok(Map<String, dynamic> r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Make this fix live?'),
        content: Text('${fixKindNames[fixKindOf('${r['fixKind']}')] ?? r['fixKind'] ?? ''}\n\n${r['summary'] ?? ''}\n\nA backup is kept; you can Undo it with one click.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('fix-ok-confirm'), onPressed: () => Navigator.pop(d, true), child: const Text('OK — make it live')),
        ],
      ),
    );
    if (yes != true) return;
    await widget.data.decide('${r['id']}', {'status': 'approved'});
    AgentLog.write(widget.store, action: 'fix_approved', target: '${r['id']}', details: {'problemId': r['problemId'], 'kind': r['fixKind'], 'files': r['files']});
  }

  Future<void> _again(Map<String, dynamic> r) async {
    final key = 'r:${r['id']}';
    final text = _box(key).text.trim();
    if (text.isEmpty) {
      await widget.data.decide('${r['id']}', {'status': 'declined'});
      AgentLog.write(widget.store, action: 'fix_declined', target: '${r['id']}');
      return;
    }
    _box(key).clear();
    await widget.data.decide('${r['id']}', {'status': 'requested', 'instruction': text});
    AgentLog.write(widget.store, action: 'fix_instruction', target: '${r['id']}', details: {'instruction': text});
  }

  Future<void> _undo(Map<String, dynamic> r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Undo this fix?'),
        content: const Text('The fix agent puts back the backup taken before this fix and makes that live.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(key: const ValueKey('fix-undo-confirm'), onPressed: () => Navigator.pop(d, true), child: const Text('Undo'))],
      ),
    );
    if (yes != true) return;
    await widget.data.decide('${r['id']}', {'status': 'undoRequested'});
    AgentLog.write(widget.store, action: 'fix_undo_requested', target: '${r['id']}');
  }

  Future<void> _explain(AppProblem p) async {
    try {
      final r = await widget.store.call('explainHealthProblem', {'key': 'fix_${p.id}', 'title': _title(p), 'error': p.message, 'where': 'screen ${p.screen}, ${p.users} people, phones ${AppProblem.topOf(p.devices)}'});
      setState(() => explained[p.id] = '${r['text'] ?? ''}');
    } catch (e) {
      setState(() => explained[p.id] = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
  }

  Future<void> _loadShot(AppProblem p) async {
    final s = await widget.data.shot?.call(p.lastShot);
    if (mounted) setState(() => shots[p.id] = s ?? '');
  }

  String _when(Object? v) {
    final t = v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    if (t == null) return '';
    final l = t.toLocal();
    return '${l.day}/${l.month} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Widget _instructionBox(String key, {required VoidCallback onSend, String label = 'What should the agent do next?'}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(children: [
      Expanded(child: TextField(key: ValueKey('fix-instruction-$key'), controller: _box(key), minLines: 1, maxLines: 4, decoration: InputDecoration(labelText: label, helperText: 'Leave empty to just not fix it', border: const OutlineInputBorder(), isDense: true))),
      const SizedBox(width: 8),
      FilledButton(key: ValueKey('fix-instruction-send-$key'), onPressed: onSend, child: const Text('Send')),
    ]),
  );

  Widget _request(Map<String, dynamic> r) {
    final status = '${r['status'] ?? 'requested'}';
    final id = '${r['id']}';
    return Container(
      key: ValueKey('fix-request-$id'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: status == 'ready' ? const Color(0xFFE3F2FD) : status == 'live' ? const Color(0xFFE8F5E9) : status == 'failed' ? const Color(0xFFFFEBEE) : const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fixStatusNames[status] ?? status, key: ValueKey('fix-status-$id'), style: const TextStyle(fontWeight: FontWeight.w600)),
        if ('${r['instruction'] ?? ''}'.isNotEmpty) Text('Your instruction: ${r['instruction']}', style: const TextStyle(fontSize: 12)),
        if (status == 'ready' || status == 'approved' || status == 'deploying' || status == 'live' || status == 'undone') ...[
          if ('${r['summary'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['summary']}')),
          Text('How it goes live: ${fixKindNames[fixKindOf('${r['fixKind']}')] ?? r['fixKind'] ?? '-'}', style: const TextStyle(fontSize: 12)),
          if (r['files'] is List) Text('Files: ${(r['files'] as List).join(', ')}', style: const TextStyle(fontSize: 12)),
          if ('${r['tests'] ?? ''}'.isNotEmpty) Text('Tests: ${r['tests']}', key: ValueKey('fix-tests-$id'), style: const TextStyle(fontSize: 12)),
          Text('AI cost of this fix: ${'${r['cost'] ?? ''}'.isEmpty ? 'not reported' : r['cost']}', key: ValueKey('fix-cost-$id'), style: const TextStyle(fontSize: 12)),
          if ('${r['diff'] ?? ''}'.isNotEmpty)
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                key: ValueKey('fix-diff-$id'),
                tilePadding: EdgeInsets.zero,
                title: const Text('The exact changes', style: TextStyle(fontSize: 13)),
                children: [Container(width: double.infinity, color: const Color(0xFF263238), padding: const EdgeInsets.all(8), child: SelectableText('${r['diff']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white)))],
              ),
            ),
        ],
        if (status == 'live') Text('Live since ${_when(r['liveAt'])}${'${r['commit'] ?? ''}'.isEmpty ? '' : ' · ${r['commit']}'} · approved by ${r['approvedBy'] ?? ''}', style: const TextStyle(fontSize: 12)),
        if (status == 'failed' && '${r['note'] ?? ''}'.isNotEmpty) Text('${r['note']}', style: const TextStyle(color: Colors.red)),
        if (status == 'ready')
          Wrap(spacing: 8, children: [
            FilledButton.icon(key: ValueKey('fix-ok-$id'), onPressed: () => _ok(r), icon: const Icon(Icons.check), label: const Text('OK — make it live')),
            OutlinedButton(key: ValueKey('fix-no-$id'), onPressed: () => setState(() => askingWhy.add('r:$id')), child: const Text("Don't fix")),
          ]),
        if (status == 'live') Wrap(spacing: 8, children: [
          OutlinedButton.icon(key: ValueKey('fix-undo-$id'), onPressed: () => _undo(r), icon: const Icon(Icons.undo), label: const Text('Undo')),
          TextButton(key: ValueKey('fix-didnt-work-$id'), onPressed: () => setState(() => askingWhy.add('r:$id')), child: const Text('It did not work')),
        ]),
        if (status == 'failed' || askingWhy.contains('r:$id')) _instructionBox('r:$id', onSend: () => _again(r)),
      ]),
    );
  }

  Widget _issue(AppProblem p, int waiting) {
    final t = fixTextOf(side: p.side, cause: p.cause);
    final r = _requestOf(p.id);
    final aiOn = aiExplainOn(widget.store);
    return Card(
      key: ValueKey('fix-issue-${p.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 18, backgroundColor: p.side == 'device' ? Colors.purple : Colors.red, child: Text('${p.users}', style: const TextStyle(color: Colors.white))),
            const SizedBox(width: 10),
            Expanded(child: Text(_title(p), style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          Text([
            '${p.users} people, ${p.count} times',
            problemKindNames[p.kind] ?? p.kind,
            problemSideNames[p.side] ?? p.side,
            if (p.devices.isNotEmpty) 'phones: ${AppProblem.topOf(p.devices)}',
            if (waiting > 0) '$waiting reports waiting for a reply',
          ].join(' · '), key: ValueKey('fix-facts-${p.id}'), style: const TextStyle(fontSize: 12)),
          SelectableText(p.message, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black54)),
          if (p.lastShot.isNotEmpty)
            shots[p.id] == null
                ? TextButton.icon(key: ValueKey('fix-shot-${p.id}'), onPressed: () => _loadShot(p), icon: const Icon(Icons.image_outlined, size: 16), label: const Text('Show the automatic screenshot'))
                : shots[p.id]!.isEmpty
                ? const Text('The screenshot was deleted.')
                : Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 360), child: Image.memory(base64Decode(shots[p.id]!)))),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('కారణం: ${t.reason}', key: ValueKey('fix-reason-${p.id}')),
              const SizedBox(height: 4),
              Text('ప్రతిపాదిత పరిష్కారం: ${t.fix}'),
              if (explained[p.id] != null) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(explained[p.id]!)),
              if (aiOn && explained[p.id] == null) TextButton.icon(onPressed: () => _explain(p), icon: const Icon(Icons.auto_awesome_outlined, size: 16), label: const Text('AI explain (Telugu, deeper)')),
            ]),
          ),
          if (r == null || r['status'] == 'declined' || r['status'] == 'undone') ...[
            const SizedBox(height: 8),
            Text(r?['status'] == 'declined' ? "You chose Don't fix. Fix it now?" : 'Fix this?', style: const TextStyle(fontWeight: FontWeight.w600)),
            Wrap(spacing: 8, children: [
              FilledButton.icon(key: ValueKey('fix-yes-${p.id}'), onPressed: () => _fix(p), icon: const Icon(Icons.build), label: const Text('Fix')),
              OutlinedButton(key: ValueKey('fix-dont-${p.id}'), onPressed: () => setState(() => askingWhy.add(p.id)), child: const Text("Don't fix")),
            ]),
            if (askingWhy.contains(p.id)) _instructionBox('p:${p.id}', onSend: () => _decline(p)),
          ] else
            _request(r),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<(List<AppProblem>, Map<String, int>)>(
    future: loaded,
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final (problems, waiting) = snap.data!;
      final people = problems.fold<int>(0, (a, p) => a + p.users);
      final waitingTotal = waiting.values.fold<int>(0, (a, b) => a + b);
      final seen = agentSeen;
      final agentOn = seen != null && DateTime.now().difference(seen) < const Duration(minutes: 45);
      return RefreshIndicator(
        onRefresh: () async {
          setState(() {
            loaded = _load();
          });
        },
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Card(
            key: const ValueKey('fix-summary'),
            color: const Color(0xFFE8EAF6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Summary (సారాంశం)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('${problems.length} open problems · $people people affected · $waitingTotal reports waiting for a reply', key: const ValueKey('fix-summary-line')),
                for (final g in _byApp(problems).entries) Text('${g.key}: ${g.value.$1} problems, ${g.value.$2} people', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(agentOn ? Icons.circle : Icons.circle_outlined, size: 12, color: agentOn ? Colors.green : Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      agentOn ? 'Fix agent on the PC is running (checked ${_when(seen)}).' : 'Fix agent on the PC is not running${seen == null ? '' : ' (last ${_when(seen)})'}: fix requests wait until it starts (tools/fix-queue/README.md).',
                      key: const ValueKey('fix-agent-state'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          if (problems.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No open problems on our side or the device side. 👍', key: ValueKey('fix-none'))),
          for (final p in problems.take(50)) _issue(p, waiting[p.id] ?? 0),
          if (requests.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 4), child: Text('Fix log', style: Theme.of(context).textTheme.titleSmall)),
            for (final r in requests.take(20))
              ListTile(
                dense: true,
                title: Text('${r['title'] ?? r['problemId']}'),
                subtitle: Text('${fixStatusNames['${r['status']}'] ?? r['status']} · asked ${_when(r['at'])}${r['approvedBy'] != null ? ' · OK by ${r['approvedBy']} ${_when(r['approvedAt'])}' : ''}${'${r['cost'] ?? ''}'.isEmpty ? '' : ' · AI ${r['cost']}'}'),
              ),
          ],
        ]),
      );
    },
  );

  Map<String, (int, int)> _byApp(List<AppProblem> list) {
    final out = <String, (int, int)>{};
    for (final p in list) {
      final name = [for (final t in appHealthTabs) if (t.$1 == p.app && t.$2 == p.platform) t.$3].firstOrNull ?? p.app;
      final v = out[name] ?? (0, 0);
      out[name] = (v.$1 + 1, v.$2 + p.users);
    }
    return out;
  }
}
