import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/problem_shots.dart';
import '../domain/health_status.dart';
import '../services/agent_log.dart';
import 'admin_frame.dart';

/// Business > AI Support reports (AI Agent + Health System part 3, 17 Nov 2026): what people sent from the AI Support box, newest
/// first, waiting ones on top: the app, who (Vendor / Staff ID and phone), what happened, the option, the cause and side, their words
/// and screenshot. The admin writes a reply and marks it Seen or Solved (the reply shows in the person's app, with a push when they
/// are signed in). "Mark the problem solved" solves every report of that problem and tells each person "Your problem is solved".
class SupportInboxPage extends StatelessWidget {
  const SupportInboxPage({super.key, required this.store, this.load, this.answer, this.solveProblem});
  final Store store;

  /// Test seams.
  final Future<List<Map<String, dynamic>>> Function()? load;
  final Future<void> Function(String id, String status, String reply)? answer;
  final Future<void> Function(String problemId)? solveProblem;

  @override
  Widget build(BuildContext context) => load != null
      ? _Inbox(store: store, load: load!, answer: answer, solveProblem: solveProblem)
      : AdminNeedsFirebase(store: store, child: _Inbox(store: store, load: () => _live(store), answer: answer, solveProblem: solveProblem));

  static Future<List<Map<String, dynamic>>> _live(Store store) async {
    final q = await store.firestore.collection('supportTickets').orderBy('at', descending: true).limit(200).get();
    return [for (final d in q.docs) {'id': d.id, ...d.data()}];
  }
}

/// Marks a problem solved (one record each time): its reports become Solved and their people are told; its screenshots go
/// (functions/modules/support and app-problems react to solvedProblems).
Future<void> markProblemSolved(Store store, String problemId, {String how = 'admin'}) async {
  await store.firestore.collection('solvedProblems').add({'problemId': problemId, 'by': FirebaseAuth.instance.currentUser?.uid ?? '', 'at': FieldValue.serverTimestamp(), 'how': how});
  AgentLog.write(store, action: 'problem_solved', target: problemId, details: {'how': how});
}

class _Inbox extends StatefulWidget {
  const _Inbox({required this.store, required this.load, this.answer, this.solveProblem});
  final Store store;
  final Future<List<Map<String, dynamic>>> Function() load;
  final Future<void> Function(String id, String status, String reply)? answer;
  final Future<void> Function(String problemId)? solveProblem;
  @override
  State<_Inbox> createState() => _InboxState();
}

class _InboxState extends State<_Inbox> {
  late Future<List<Map<String, dynamic>>> data = widget.load();
  String filter = 'waiting';
  final replies = <String, TextEditingController>{};
  final notes = <String, String>{};

  @override
  void dispose() {
    for (final c in replies.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _answer(Map<String, dynamic> t, String status) async {
    final id = '${t['id']}';
    final reply = replies[id]?.text.trim() ?? '';
    try {
      await (widget.answer ?? (id, status, reply) async => widget.store.call('answerSupportTicket', {'id': id, 'status': status, if (reply.isNotEmpty) 'reply': reply}))(id, status, reply);
      setState(() {
        notes[id] = status == 'solved' ? 'Solved. The person was told.' : 'Marked seen.';
        data = widget.load();
      });
    } catch (e) {
      setState(() => notes[id] = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
  }

  Future<void> _solveProblem(String problemId) async {
    await (widget.solveProblem ?? (p) => markProblemSolved(widget.store, p))(problemId);
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Problem marked solved: its reports are solved and the people are told.')));
      setState(() {
        data = widget.load();
      });
    }
  }

  /// One screenshot: a US-bucket path, or the ticket id of the version before 18 Nov 2026 (supportShots).
  Future<void> _shot(String ref) async {
    final b64 = await loadProblemShot(widget.store, ref, oldCollection: 'supportShots');
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => Dialog(child: b64.isEmpty ? const Padding(padding: EdgeInsets.all(24), child: Text('The screenshot was deleted.')) : InteractiveViewer(child: Image.memory(base64Decode(b64)))));
  }

  String _when(Object? v) {
    final t = v is Timestamp ? v.toDate() : v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    if (t == null) return '';
    return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _ticket(Map<String, dynamic> t) {
    final id = '${t['id']}';
    final status = '${t['status'] ?? 'sent'}';
    final app = [for (final a in appHealthTabs) if (a.$1 == t['app'] && a.$2 == t['platform']) a.$3].firstOrNull ?? '${t['app']}';
    final c = replies.putIfAbsent(id, () => TextEditingController(text: '${t['reply'] ?? ''}'));
    return Card(
      key: ValueKey('support-ticket-$id'),
      color: status == 'sent' ? const Color(0xFFFFF3E0) : status == 'solved' ? const Color(0xFFF1F8E9) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Chip(label: Text(status == 'sent' ? 'Waiting' : status == 'seen' ? 'Seen' : 'Solved'), visualDensity: VisualDensity.compact),
            const SizedBox(width: 8),
            Expanded(child: Text('$app · ${problemSideNames[t['side']] ?? t['side'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(_when(t['at']), style: const TextStyle(fontSize: 12)),
          ]),
          if ('${t['message'] ?? ''}'.isNotEmpty) SelectableText('${t['message']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          // One ticket per problem (18 Nov 2026): how many times and people, and each person's own words.
          if (((t['count'] as num?)?.toInt() ?? 1) > 1)
            Text('${t['count']} times · ${peopleText((t['users'] as num?)?.toInt() ?? 1, t['usersMore'] == true)}',
                key: ValueKey('support-count-$id'), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (t['notes'] is List && (t['notes'] as List).isNotEmpty)
            for (final n in (t['notes'] as List).whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('"${n['text'] ?? ''}"${'${n['userCode'] ?? ''}'.isEmpty ? '' : ' — ${n['userCode']}'}${'${n['phone'] ?? ''}'.isEmpty ? '' : ' 📞 ${n['phone']}'}', style: const TextStyle(fontSize: 15)),
              )
          else if ('${t['text'] ?? ''}'.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('"${t['text']}"', style: const TextStyle(fontSize: 15))),
          Text([
            if ('${t['screen'] ?? ''}'.isNotEmpty) 'screen ${t['screen']}',
            if ('${t['option'] ?? ''}'.isNotEmpty) 'option "${t['option']}"',
            if ('${t['cause'] ?? ''}'.isNotEmpty) 'cause ${t['cause']}',
            if ('${t['userCode'] ?? ''}'.isNotEmpty) '${t['userCode']}',
            if ('${t['phone'] ?? ''}'.isNotEmpty) '📞 ${t['phone']}',
            if ('${t['version'] ?? ''}'.isNotEmpty) 'v${t['version']}',
            if ('${t['device'] ?? ''}'.isNotEmpty) '${t['device']}',
            if (t['auto'] == true) 'sent automatically',
            'language ${t['lang'] ?? 'en'}',
          ].join(' · '), style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('support-reply-$id'),
            controller: c,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Reply (shows in their app)', border: OutlineInputBorder(), isDense: true),
          ),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final (i, path) in [for (final p in (t['shotPaths'] is List ? t['shotPaths'] as List : const [])) '$p'].indexed)
              TextButton.icon(key: ValueKey('support-shot-$id-$i'), onPressed: () => _shot(path), icon: const Icon(Icons.image_outlined, size: 16), label: Text('Screenshot ${i + 1}')),
            if (t['shot'] == true && t['shotPaths'] is! List) TextButton.icon(onPressed: () => _shot(id), icon: const Icon(Icons.image_outlined, size: 16), label: const Text('Screenshot')),
            OutlinedButton(key: ValueKey('support-seen-$id'), onPressed: () => _answer(t, 'seen'), child: const Text('Seen + send reply')),
            FilledButton(key: ValueKey('support-solved-$id'), onPressed: () => _answer(t, 'solved'), child: const Text('Solved')),
            if ('${t['problemId'] ?? ''}'.isNotEmpty)
              TextButton(key: ValueKey('support-solve-problem-$id'), onPressed: () => _solveProblem('${t['problemId']}'), child: const Text('Mark the whole problem solved')),
          ]),
          if (notes[id] != null) Text(notes[id]!, key: ValueKey('support-note-$id')),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: data,
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final all = snap.data!;
      final waiting = all.where((t) => t['status'] == 'sent').length;
      final shown = [for (final t in all) if (filter == 'all' || (filter == 'waiting' && t['status'] != 'solved') || t['status'] == filter) t];
      return RefreshIndicator(
        onRefresh: () async => setState(() {
          data = widget.load();
        }),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Text('AI Support reports: $waiting waiting for a reply', key: const ValueKey('support-waiting'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final f in const [('waiting', 'Open'), ('sent', 'Waiting'), ('seen', 'Seen'), ('solved', 'Solved'), ('all', 'All')])
              ChoiceChip(key: ValueKey('support-filter-${f.$1}'), label: Text(f.$2), selected: filter == f.$1, onSelected: (_) => setState(() => filter = f.$1)),
          ]),
          if (shown.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing here. 👍', key: ValueKey('support-none'))),
          for (final t in shown) _ticket(t),
        ]),
      );
    },
  );
}
