import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../data/store.dart';

/// Customer complaint review — fully self-contained, independent of the
/// generic EntryEditor/admin shell and the other moderation pages.
class ComplaintModerationPage extends StatelessWidget {
  const ComplaintModerationPage({super.key, required this.store});
  final Store store;
  Future<void> review(BuildContext context, String id, String status) async {
    final resolution = TextEditingController();
    final submit = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: Text('$status complaint'),
      content: TextField(controller: resolution, maxLines: 4, decoration: const InputDecoration(labelText: 'Resolution or review note')),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Save'))],
    ));
    if (submit != true) return;
    try {
      await FirebaseFunctions.instance.httpsCallable('reviewComplaint').call({'complaintId': id, 'status': status, 'resolution': resolution.text.trim()});
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Complaint updated')));
    } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    resolution.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Complaint review')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('complaints').limit(100).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Complaints could not load.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text('No complaints.'));
        return ListView(padding: const EdgeInsets.all(20), children: [
          for (final doc in snapshot.data!.docs) Card(child: ExpansionTile(
            title: Text(doc.data()['subject']?.toString() ?? doc.id),
            subtitle: Text('${doc.data()['status']} • Customer ${doc.data()['customerId']}'),
            children: [
              ListTile(title: Text(doc.data()['resolution']?.toString() ?? 'No resolution yet.')),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: doc.reference.collection('messages').snapshots(), builder: (_, messages) => Column(children: [for (final message in messages.data?.docs ?? const []) ListTile(dense: true, title: Text(message.data()['body']?.toString() ?? ''), subtitle: Text(message.data()['authorRole']?.toString() ?? ''))])),
              OverflowBar(children: [TextButton(onPressed: () => review(context, doc.id, 'in_review'), child: const Text('In review')), TextButton(onPressed: () => review(context, doc.id, 'resolved'), child: const Text('Resolve')), TextButton(onPressed: () => review(context, doc.id, 'closed'), child: const Text('Close'))]),
            ],
          )),
        ]);
      },
    ),
  );
}
