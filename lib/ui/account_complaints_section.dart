import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';

/// The customer's own complaint list on the account page. Read-only: opening
/// a new complaint is a separate dialog (see `AccountPage.showComplaintDialog`).
class AccountComplaintsSection extends StatelessWidget {
  const AccountComplaintsSection({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('complaints')
        .where('customerId', isEqualTo: store.user!.uid)
        .limit(30)
        .snapshots(),
    builder: (context, snap) => Column(children: [
      for (final complaint in snap.data?.docs ?? const [])
        ListTile(
          title: Text(complaint.data()['subject']?.toString() ?? 'Complaint'),
          subtitle: Text('${complaint.data()['status']} • ${complaint.data()['resolution'] ?? 'Awaiting review'}'),
        ),
    ]),
  );
}
