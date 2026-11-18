import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/health_status.dart';
import '../services/agent_log.dart';
import '../services/problem_shots.dart';
import 'admin_frame.dart';
import 'agent_ai_settings.dart';

/// Business > App Health (owner spec G, 17 Nov 2026): one tab each for the Vendor, Staff and User Android apps (and the website and the
/// admin panel): how many problems of each kind, the problems with the MOST AFFECTED PEOPLE first, then the most errors (AI Agent +
/// Health System part 1), each with its side (user / device / our), phone models, version, screen, option, the Vendor / Staff ID and its
/// automatic screenshot, and the "Report a problem" messages with their screenshots. Crash stacks are also in Firebase Crashlytics.
class AppHealthPage extends StatelessWidget {
  const AppHealthPage({super.key, required this.store, this.load});
  final Store store;

  /// Test seam: the problems and reports of one tab, instead of Firestore.
  final Future<(List<AppProblem>, List<Map<String, dynamic>>)> Function(String app, String platform)? load;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: appHealthTabs.length,
    child: Column(children: [
      TabBar(isScrollable: true, tabs: [for (final t in appHealthTabs) Tab(key: ValueKey('app-health-tab-${t.$1}-${t.$2}'), text: t.$3)]),
      Expanded(
        child: TabBarView(children: [
          for (final t in appHealthTabs)
            load != null
                ? _AppTab(store: store, app: t.$1, platform: t.$2, load: load!)
                : AdminNeedsFirebase(store: store, child: _AppTab(store: store, app: t.$1, platform: t.$2, load: (a, p) => _loadLive(store, a, p))),
        ]),
      ),
    ]),
  );
}

/// One app's problems (by document id, so no extra index is needed) and its reports. At most 300 problems and 100 reports.
Future<(List<AppProblem>, List<Map<String, dynamic>>)> _loadLive(Store store, String app, String platform) async {
  final db = store.firestore;
  final prefix = '$app~$platform~';
  final problems = await db.collection('appProblems').orderBy(FieldPath.documentId).startAt([prefix]).endAt(['$prefix']).limit(300).get();
  final reports = platform == 'web' && app == 'admin'
      ? null
      : await db.collection('problemReports').where('app', isEqualTo: app).limit(100).get();
  final list = [
    for (final d in reports?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
      if ('${d.data()['platform']}' == platform) {'id': d.id, ...d.data()},
  ]..sort((a, b) => ((b['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
  return (mostAffectedFirst([for (final d in problems.docs) AppProblem.from(d.id, d.data())]), list);
}

class _AppTab extends StatefulWidget {
  const _AppTab({required this.store, required this.app, required this.platform, required this.load});
  final Store store;
  final String app, platform;
  final Future<(List<AppProblem>, List<Map<String, dynamic>>)> Function(String app, String platform) load;
  @override
  State<_AppTab> createState() => _AppTabState();
}

class _AppTabState extends State<_AppTab> with AutomaticKeepAliveClientMixin {
  late Future<(List<AppProblem>, List<Map<String, dynamic>>)> data = widget.load(widget.app, widget.platform);
  String kind = '';
  String side = '';
  final explained = <String, String>{};

  @override
  bool get wantKeepAlive => true;

  String _when(DateTime? t) {
    if (t == null) return '';
    final l = t.toLocal();
    return '${l.day}/${l.month} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _explain(AppProblem p) async {
    try {
      final r = await widget.store.call('explainHealthProblem', {'key': 'app_${p.id}', 'title': '${problemKindNames[p.kind] ?? p.kind} in the ${widget.app} app', 'error': p.message, 'where': 'screen ${p.screen}, version ${p.version}, ${p.device}'});
      if (mounted) setState(() => explained[p.id] = '${r['text'] ?? ''}');
    } catch (e) {
      if (mounted) setState(() => explained[p.id] = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
  }

  Future<void> _setStatus(String id, String status) async {
    await widget.store.firestore.collection('problemReports').doc(id).update({'status': status});
    AgentLog.write(widget.store, action: 'report_$status', target: id);
    setState(() {
      data = widget.load(widget.app, widget.platform);
    });
  }

  Widget _report(Map<String, dynamic> r) {
    final at = (r['at'] is Timestamp) ? (r['at'] as Timestamp).toDate() : null;
    final status = '${r['status'] ?? 'new'}';
    return Card(
      key: ValueKey('app-health-report-${r['id']}'),
      color: status == 'new' ? const Color(0xFFFFF3E0) : null,
      child: ListTile(
        leading: const Icon(Icons.bug_report_outlined),
        title: Text('${r['text'] ?? ''}'),
        subtitle: Text([
          _when(at),
          if ('${r['userCode'] ?? ''}'.isNotEmpty) '${r['userCode']}',
          if ('${r['version'] ?? ''}'.isNotEmpty) 'v${r['version']}',
          if ('${r['device'] ?? ''}'.isNotEmpty) '${r['device']}',
          if ('${r['screen'] ?? ''}'.isNotEmpty) 'screen ${r['screen']}',
        ].join(' · ')),
        trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if ('${r['screenshotPath'] ?? ''}'.isNotEmpty)
            IconButton(tooltip: 'Screenshot', icon: const Icon(Icons.image_outlined), onPressed: () => _showShot('${r['screenshotPath']}')),
          DropdownButton<String>(
            value: const ['new', 'seen', 'fixed'].contains(status) ? status : 'new',
            items: const [DropdownMenuItem(value: 'new', child: Text('New')), DropdownMenuItem(value: 'seen', child: Text('Seen')), DropdownMenuItem(value: 'fixed', child: Text('Fixed'))],
            onChanged: widget.store.live ? (v) => _setStatus('${r['id']}', v ?? 'new') : null,
          ),
        ]),
      ),
    );
  }

  Future<void> _showShot(String path) async {
    // Reports before 18 Nov 2026 kept their screenshot in the Mumbai bucket; new ones are in the US bucket.
    if (path.startsWith('problemReports/')) {
      final url = await FirebaseStorage.instance.ref(path).getDownloadURL();
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (d) => Dialog(child: InteractiveViewer(child: Image.network(url))));
      return;
    }
    await _showAutoShot(path);
  }

  /// One screenshot of a problem (the US bucket, or an appShots record of the version before), shown full size.
  Future<void> _showAutoShot(String ref) async {
    final data = await loadProblemShot(widget.store, ref);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(child: data.isEmpty ? const Padding(padding: EdgeInsets.all(24), child: Text('The screenshot was deleted (solved or older than 30 days).')) : InteractiveViewer(child: Image.memory(base64Decode(data)))),
    );
  }

  Widget _problemCard(AppProblem p, bool aiOn) => Card(
    key: ValueKey('app-health-problem-${p.id}'),
    color: p.solved ? const Color(0xFFF1F8E9) : null,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Tooltip(
            message: '${peopleText(p.users, p.usersMore)}, ${p.count} times',
            child: Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.people_alt_outlined, size: 16),
              label: Text('${p.users}${p.usersMore ? '+' : ''} · ${p.count}×', key: ValueKey('app-health-impact-${p.id}')),
              backgroundColor: p.kind == 'crash' || p.users >= 5 ? const Color(0xFFFFCDD2) : const Color(0xFFFFE0B2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(problemKindNames[p.kind] ?? p.kind, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(_when(p.lastAt), style: const TextStyle(fontSize: 12)),
        ]),
        Wrap(spacing: 6, children: [
          Chip(visualDensity: VisualDensity.compact, label: Text(problemSideNames[p.side] ?? p.side, style: const TextStyle(fontSize: 12)), backgroundColor: p.side == 'user' ? const Color(0xFFE3F2FD) : p.side == 'device' ? const Color(0xFFF3E5F5) : const Color(0xFFFFEBEE)),
          if (p.solved) const Chip(visualDensity: VisualDensity.compact, label: Text('Solved', style: TextStyle(fontSize: 12))),
        ]),
        SelectableText(p.message, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        Text([
          if (p.screen.isNotEmpty) 'screen ${p.screen}',
          if (p.option.isNotEmpty) 'option "${p.option}"',
          if (p.version.isNotEmpty) 'v${p.version}',
          if (p.userCode.isNotEmpty) p.userCode,
          if (p.network.isNotEmpty) p.network,
          if (p.ms != null) '${(p.ms! / 1000).toStringAsFixed(1)} s',
        ].join(' · '), style: const TextStyle(fontSize: 12, color: Colors.black54)),
        if (p.devices.isNotEmpty) Text('Phones: ${AppProblem.topOf(p.devices)}', key: ValueKey('app-health-devices-${p.id}'), style: const TextStyle(fontSize: 12)),
        if (p.oses.isNotEmpty && p.platform == 'android') Text('Android: ${AppProblem.topOf(p.oses)}', style: const TextStyle(fontSize: 12)),
        // The last 3 times it happened (one record per problem: no record per person).
        for (final (i, e) in p.examples.indexed)
          Text([
            _when(e['at']),
            if ('${e['version'] ?? ''}'.isNotEmpty) 'v${e['version']}',
            if ('${e['model'] ?? ''}'.isNotEmpty) '${e['model']}',
            if ('${e['os'] ?? ''}'.isNotEmpty && e['os'] != 'unknown') '${e['os']}',
            if ('${e['role'] ?? ''}'.isNotEmpty) '${e['role']}',
            if ('${e['userCode'] ?? ''}'.isNotEmpty) '${e['userCode']}',
            if ('${e['phone'] ?? ''}'.isNotEmpty) '📞 ${e['phone']}',
            if ('${e['network'] ?? ''}'.isNotEmpty) '${e['network']}',
          ].join(' · '), key: ValueKey('app-health-example-${p.id}-$i'), style: const TextStyle(fontSize: 12, color: Colors.black54)),
        Wrap(spacing: 4, children: [
          for (final (i, shot) in p.screenshots.indexed)
            TextButton.icon(
              key: ValueKey('app-health-shot-${p.id}-$i'),
              onPressed: () => _showAutoShot(shot),
              icon: const Icon(Icons.image_outlined, size: 16),
              label: Text(p.screenshots.length == 1 ? 'Screenshot' : 'Screenshot ${i + 1}'),
            ),
          if (aiOn && explained[p.id] == null)
            TextButton.icon(onPressed: () => _explain(p), icon: const Icon(Icons.auto_awesome_outlined, size: 16), label: const Text('AI explain (Telugu)')),
        ]),
        if (explained[p.id] != null) Container(padding: const EdgeInsets.all(8), color: const Color(0xFFFFF8E1), child: SelectableText(explained[p.id]!)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final aiOn = aiExplainOn(widget.store);
    return FutureBuilder<(List<AppProblem>, List<Map<String, dynamic>>)>(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (loaded, reports) = snap.data!;
        final problems = mostAffectedFirst(loaded);
        final counts = countsByKind(problems);
        final shown = [for (final p in problems) if ((kind.isEmpty || p.kind == kind) && (side.isEmpty || p.side == side)) p];
        final bySide = <String, int>{for (final s in problemSideNames.keys) s: problems.where((p) => p.side == s).length};
        return RefreshIndicator(
          onRefresh: () async => setState(() {
            data = widget.load(widget.app, widget.platform);
          }),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(label: Text('All (${counts.values.fold(0, (a, b) => a + b)})'), selected: kind.isEmpty, onSelected: (_) => setState(() => kind = '')),
                for (final e in counts.entries)
                  ChoiceChip(key: ValueKey('app-health-kind-${e.key}'), label: Text('${problemKindNames[e.key] ?? e.key}: ${e.value}'), selected: kind == e.key, onSelected: (_) => setState(() => kind = e.key)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(label: const Text('Every side'), selected: side.isEmpty, onSelected: (_) => setState(() => side = '')),
                for (final e in problemSideNames.entries)
                  ChoiceChip(key: ValueKey('app-health-side-${e.key}'), label: Text('${e.value}: ${bySide[e.key]}'), selected: side == e.key, onSelected: (_) => setState(() => side = e.key)),
              ]),
              if (reports.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 4), child: Text('"Report a problem" messages (${reports.where((r) => r['status'] == 'new').length} new)', style: Theme.of(context).textTheme.titleSmall)),
                for (final r in reports.take(50)) _report(r),
              ],
              Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 4), child: Text('Problems, most affected people first', key: const ValueKey('app-health-order'), style: Theme.of(context).textTheme.titleSmall)),
              if (shown.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No problems reported. 👍', key: ValueKey('app-health-none'))),
              for (final p in shown) _problemCard(p, aiOn),
            ],
          ),
        );
      },
    );
  }
}
