import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';

/// Read-only viewer of aiAgentAuditLog (written only by functions/ai-agent-*.js;
/// every propose/confirm/reject/execute/interpret/voice/webauthn/monitoring/
/// backup event lands here). Deleting this file just removes the viewer —
/// the log itself keeps being written regardless.
class AiAgentAuditLogView extends StatelessWidget {
  const AiAgentAuditLogView({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('aiAgentAuditLog').orderBy('at', descending: true).limit(100).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('Audit log could not load.'));
      final docs = snapshot.data?.docs ?? const [];
      if (docs.isEmpty) return const Center(child: Text('No AI Agent activity yet.'));
      return ListView.builder(
        itemCount: docs.length,
        itemBuilder: (context, i) {
          final d = docs[i].data();
          final at = (d['at'] as Timestamp?)?.toDate();
          return ListTile(
            dense: true,
            leading: Icon(d['result']?.toString().startsWith('fail') == true || d['result'] == 'denied' ? Icons.error_outline : Icons.check_circle_outline),
            title: Text('${d['type']}${d['action'] != null ? ' • ${d['action']}' : ''}'),
            subtitle: Text('${d['detail'] ?? ''}${d['result'] != null ? ' (${d['result']})' : ''}'),
            trailing: at == null ? null : Text('${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'),
          );
        },
      );
    },
  );
}
