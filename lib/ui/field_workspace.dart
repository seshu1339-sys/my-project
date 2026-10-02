import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import 'field_entry_form.dart';

/// Shown only once the staff member's fieldStaff doc is 'active'. Lists past
/// submissions and starts a new one; the server independently re-checks
/// 'active' status for every submission regardless of what this screen shows.
class FieldWorkspace extends StatefulWidget {
  const FieldWorkspace({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;
  @override
  State<FieldWorkspace> createState() => _FieldWorkspaceState();
}

class _FieldWorkspaceState extends State<FieldWorkspace> {
  Store get store => widget.store;
  String get uid => widget.uid;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Field entries', style: Theme.of(context).textTheme.headlineSmall),
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldStaff').doc(uid).snapshots(),
        builder: (context, snapshot) {
          final code = snapshot.data?.data()?['staffCode'] as String?;
          if (code == null) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(top: 4), child: Text('Staff ID: $code', style: Theme.of(context).textTheme.bodyMedium));
        },
      ),
      const SizedBox(height: 8),
      const Text('Capture an item at a vendor shop. Nothing you submit is visible to customers until an administrator approves it.'),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => FieldEntryForm(store: store))),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('New entry'),
      ),
      const SizedBox(height: 24),
      Text('My submissions', style: Theme.of(context).textTheme.titleLarge),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldSubmissions').where('staffUid', isEqualTo: uid).limit(100).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Submissions could not load.'));
          final docs = [...snapshot.data?.docs ?? const []]..sort((a, b) {
            final ta = a.data()['submittedAt'] as Timestamp?;
            final tb = b.data()['submittedAt'] as Timestamp?;
            if (ta == null || tb == null) return 0;
            return tb.compareTo(ta);
          });
          if (docs.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No submissions yet.'));
          return Column(children: [for (final doc in docs) _submissionTile(doc)]);
        },
      ),
    ],
  );

  Widget _submissionTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final item = data['item'] as Map<String, dynamic>? ?? const {};
    final shop = data['shop'] as Map<String, dynamic>?;
    final shopId = data['shopId']?.toString() ?? '';
    final shopLabel = shopId.isNotEmpty ? 'Existing shop' : (shop?['name']?.toString() ?? 'New shop');
    final status = data['status']?.toString() ?? 'pending';
    final reason = data['decisionReason']?.toString() ?? '';
    final statusText = switch (status) {
      'approved' => 'Approved',
      'rejected' => 'Rejected${reason.isEmpty ? '' : ': $reason'}',
      _ => 'Pending admin review',
    };
    return Card(child: ListTile(
      title: Text('${item['name']}'),
      subtitle: Text('₹${item['price']} • Stock ${item['stock']} • $shopLabel\n$statusText'),
      isThreeLine: true,
    ));
  }
}
