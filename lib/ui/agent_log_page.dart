import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'admin_frame.dart';

/// Settings > Agent log: every command-box action, newest first (who, what, when; owner spec I). Read only: nobody can edit or delete
/// a line (firestore.rules agentLog). The latest 200 are shown.
class AgentLogPage extends StatelessWidget {
  const AgentLogPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => AdminNeedsFirebase(
    store: store,
    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('agentLog').orderBy('at', descending: true).limit(200).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load the log: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No agent actions yet.'));
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final at = (d['at'] as Timestamp?)?.toDate().toLocal();
            final when = at == null ? '' : '${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
            return ListTile(
              dense: true,
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text('${d['action']}${'${d['target'] ?? ''}'.isEmpty ? '' : ' → ${d['target']}'}'),
              subtitle: Text([if ('${d['command'] ?? ''}'.isNotEmpty) '"${d['command']}"', '${d['email'] ?? d['uid']}', when].join(' · ')),
            );
          },
        );
      },
    ),
  );
}
