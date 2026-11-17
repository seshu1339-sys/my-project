import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/store.dart';
import '../domain/support_texts.dart';
import '../services/app_monitoring.dart';

/// "My problem reports" (AI Agent + Health System part 3): what the person sent from the AI Support box, with its status
/// Sent → Seen → Solved and the LocaMarket team's reply, in their language. Their own reports only: by account when signed in, else by
/// this device (functions/modules/support mySupportTickets).
class MySupportPage extends StatefulWidget {
  const MySupportPage({super.key, required this.store, this.load});
  final Store store;

  /// Test seam: the reports instead of the server.
  final Future<List<Map<String, dynamic>>> Function()? load;

  /// Set once the person sent a report: only then does the app look for replies when it opens (no call for everyone else).
  static const hasTicketsKey = 'supportHasTickets';

  /// The newest reply the person has seen (ms since epoch).
  static const seenReplyKey = 'supportSeenReplyAt';

  static Future<List<Map<String, dynamic>>> fetch(Store store) async {
    final r = await store.call('mySupportTickets', {'deviceId': AppMonitoring.deviceId});
    return [for (final t in (r['tickets'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
  }

  /// True when the team replied (or solved) after the last time the person looked. Never throws.
  static Future<bool> hasNewReply(Store store, {Future<List<Map<String, dynamic>>> Function()? load}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(hasTicketsKey) != true) return false;
      final seen = prefs.getInt(seenReplyKey) ?? 0;
      final list = await (load ?? () => fetch(store))();
      return list.any((t) => ((t['replyAt'] as num?)?.toInt() ?? 0) > seen);
    } catch (_) {
      return false;
    }
  }

  @override
  State<MySupportPage> createState() => _MySupportPageState();
}

class _MySupportPageState extends State<MySupportPage> {
  late final Future<List<Map<String, dynamic>>> data = (widget.load ?? () => MySupportPage.fetch(widget.store))().then((list) async {
    final newest = list.fold<int>(0, (m, t) => ((t['replyAt'] as num?)?.toInt() ?? 0) > m ? (t['replyAt'] as num).toInt() : m);
    try {
      (await SharedPreferences.getInstance()).setInt(MySupportPage.seenReplyKey, newest);
    } catch (_) {}
    return list;
  });

  String get lang => supportLang(widget.store.language);

  String _when(int ms) {
    if (ms == 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(supportWord('myReports', lang))),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '')));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!;
        if (list.isEmpty) return Center(child: Text(supportWord('none', lang), key: const ValueKey('my-support-none')));
        return ListView(padding: const EdgeInsets.all(12), children: [
          for (final t in list)
            Card(
              key: ValueKey('my-support-${t['id']}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Chip(
                      label: Text(supportStatus('${t['status']}', lang), style: const TextStyle(color: Colors.white)),
                      backgroundColor: t['status'] == 'solved' ? Colors.green : t['status'] == 'seen' ? Colors.orange : Colors.blueGrey,
                    ),
                    const Spacer(),
                    Text(_when((t['at'] as num?)?.toInt() ?? 0), style: const TextStyle(fontSize: 12)),
                  ]),
                  if ('${t['text'] ?? ''}'.isNotEmpty) Text('${t['text']}'),
                  if ('${t['reply'] ?? ''}'.isNotEmpty)
                    Container(
                      key: ValueKey('my-support-reply-${t['id']}'),
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                      child: Text('${supportWord('reply', lang)} ${t['reply']}'),
                    ),
                ]),
              ),
            ),
        ]);
      },
    ),
  );
}
