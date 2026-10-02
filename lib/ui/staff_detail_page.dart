import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../data/store.dart';
import 'moderation_dialogs.dart';

/// One field-staff member's full admin profile, reached from the unified
/// admin search (admin_search.dart). Consolidates the same per-staff controls
/// FieldModerationPage already exposes inline in its long list — pending
/// access decision and suspension — calling the exact same existing Cloud
/// Functions. field_moderation.dart itself is not touched.
/// Also shows what that inline list leaves out: the mandatory registration
/// photo, phone number, and any of this staff member's pending fieldSubmissions.
class StaffDetailPage extends StatelessWidget {
  const StaffDetailPage({super.key, required this.store, required this.staffUid});
  final Store store;
  final String staffUid;

  Future<void> _decide(BuildContext context, String function, Map<String, dynamic> data) async {
    try {
      await FirebaseFunctions.instance.httpsCallable(function).call(data);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _review(BuildContext context, {required bool approved}) =>
      _decide(context, 'reviewFieldStaff', {'staffUid': staffUid, 'approved': approved, 'reason': ''});

  Future<void> _setSuspension(BuildContext context, String name, {required bool suspend}) async {
    final reason = await showSuspensionDialog(
      context,
      name: name,
      suspend: suspend,
      suspendBody: 'They will not be able to submit new entries until reinstated.',
      reinstateBody: 'They will be able to submit entries again.',
    );
    if (reason == null || !context.mounted) return;
    await _decide(context, 'setFieldStaffSuspension', {'staffUid': staffUid, 'suspended': suspend, 'reason': reason});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Field staff profile')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('fieldStaff').doc(staffUid).snapshots(),
      builder: (context, snapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldSubmissions').where('staffUid', isEqualTo: staffUid).where('status', isEqualTo: 'pending').limit(50).snapshots(),
        builder: (context, pendingSnapshot) {
        final data = snapshot.data?.data();
        if (data == null) return const Center(child: Text('This field-staff record could not be found.'));
        final pendingSubmissions = pendingSnapshot.data?.docs ?? const [];
        final name = data['name']?.toString().isNotEmpty == true ? data['name'].toString() : staffUid;
        final code = data['staffCode'] as String?;
        final status = data['status']?.toString() ?? '';
        final suspended = status == 'suspended';
        final pending = status == 'pending';
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text(name, style: Theme.of(context).textTheme.headlineSmall),
          if (code != null) Text('Staff ID: $code'),
          Text('UID: $staffUid', style: Theme.of(context).textTheme.bodySmall),
          if ((data['email'] ?? '').toString().isNotEmpty) Text(data['email'].toString()),
          if ((data['phone'] ?? '').toString().isNotEmpty) Text('Phone: ${data['phone']}'),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Photo', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ApplicationPhoto(label: 'Staff photo', path: data['staffPhotoPath']?.toString()),
          ]))),
          const SizedBox(height: 16),
          if (pendingSubmissions.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.pending_actions, size: 18),
              const SizedBox(width: 8),
              Text('Pending submissions (${pendingSubmissions.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            for (final doc in pendingSubmissions) Padding(padding: const EdgeInsets.only(top: 8), child: Text(
              '• ${(doc.data()['item'] as Map<String, dynamic>?)?['name'] ?? doc.id}',
            )),
          ]))),
          const SizedBox(height: 16),
          if (pending) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Access request pending approval', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            OverflowBar(children: [
              FilledButton(onPressed: () => _review(context, approved: true), child: const Text('Approve')),
              OutlinedButton(onPressed: () => _review(context, approved: false), child: const Text('Reject')),
            ]),
          ]))),
          if (!pending) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Status: ${suspended ? 'Suspended' : status}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (suspended && (data['decisionReason'] ?? '').toString().trim().isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('Reason: ${data['decisionReason']}')),
            const SizedBox(height: 12),
            suspended
                ? FilledButton(onPressed: () => _setSuspension(context, name, suspend: false), child: const Text('Reinstate'))
                : FilledButton.tonal(onPressed: () => _setSuspension(context, name, suspend: true), child: const Text('Suspend')),
          ]))),
        ]);
        },
      ),
    ),
  );
}
