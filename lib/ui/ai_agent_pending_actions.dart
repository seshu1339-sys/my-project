import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'ai_agent_confirmation.dart';

/// Lists this admin's pending AI Agent actions and lets them Approve/Reject.
/// On approval, functions/ai-agent-executor.js's confirmAgentAction returns a
/// descriptor of exactly which existing write to perform — this widget is the
/// one place that actually performs it, through the SAME Store.firestore
/// merge write or store.call() the rest of the admin UI already uses for that
/// exact action. Nothing here re-implements vendor/staff/layout/content logic.
class AiAgentPendingActions extends StatelessWidget {
  const AiAgentPendingActions({super.key, required this.store});
  final Store store;

  Future<void> _decide(BuildContext context, String pendingActionId, String tier, String preview, {required bool reject}) async {
    final data = <String, dynamic>{'pendingActionId': pendingActionId};
    if (reject) {
      data['reject'] = true;
    } else if (tier == 'sensitive') {
      final pin = await promptAgentPin(context, preview);
      if (pin == null) return;
      data['pin'] = pin;
    } else if (tier == 'critical') {
      if (!context.mounted) return;
      final verified = await ensureFreshOtp(context, store, preview);
      if (!verified) return;
    }

    Map<String, dynamic> result;
    try {
      result = await store.call('confirmAgentAction', data);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (result['status'] == 'rejected') {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rejected.')));
      return;
    }

    final execute = result['execute'] as Map?;
    if (execute == null) {
      // kind:'serverAction' (GitHub/Play Console/...): the server already
      // performed the write itself inside confirmAgentAction — there is
      // nothing left for this client to execute.
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Done.')));
      return;
    }
    var success = true;
    String? error;
    try {
      if (execute['kind'] == 'callable') {
        await store.call(execute['callableName'] as String, Map<String, dynamic>.from(execute['callableData'] as Map));
      } else if (execute['kind'] == 'firestoreMerge') {
        await store.firestore
            .collection(execute['collection'] as String)
            .doc(execute['docId'] as String)
            .set(Map<String, dynamic>.from(execute['data'] as Map), SetOptions(merge: true));
      }
    } catch (e) {
      success = false;
      error = '$e';
    }
    try {
      await store.call('reportAgentActionExecuted', {
        'pendingActionId': pendingActionId,
        'success': success,
        'error': ?error,
      });
    } catch (_) {
      // Best-effort reporting only — the real action already happened or failed above.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? 'Done.' : 'Failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = store.user?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore
          .collection('aiAgentPendingActions')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Pending actions could not load.'));
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) return const Center(child: Text('Nothing is waiting for your approval.'));
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final d = doc.data();
            final tier = (d['tier'] ?? 'safe').toString();
            final preview = (d['preview'] ?? '').toString();
            return Card(child: ListTile(
              title: Text(preview),
              subtitle: Text('Tier: $tier'),
              trailing: Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: () => _decide(context, doc.id, tier, preview, reject: true), child: const Text('Reject')),
                FilledButton(onPressed: () => _decide(context, doc.id, tier, preview, reject: false), child: const Text('Apply')),
              ]),
            ));
          },
        );
      },
    );
  }
}
