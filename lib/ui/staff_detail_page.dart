import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'moderation_dialogs.dart';
import 'shop_map.dart';

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

  Future<void> _decide(BuildContext context, String function, Map<String, dynamic> data) =>
      runModerationAction(context, () => store.call(function, data));

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

  /// Cancels the staff ID for good (owner, 13 Nov 2026): never reinstated or given again; their cell is free and their vendors move to
  /// the office (functions/field-assistant.js cancelFieldStaff).
  Future<void> _cancel(BuildContext context, String code) async {
    final reason = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Cancel staff ID $code for good?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('The ID is closed for good and never given again. Their cell becomes free and their linked vendors move to the office.'),
            TextField(
              key: const ValueKey('staff-cancel-reason'),
              controller: reason,
              maxLines: 2,
              maxLength: 500,
              onChanged: (_) => setDialogState(() {}),
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Back')),
            FilledButton(
              key: const ValueKey('staff-cancel-go'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: reason.text.trim().length < 3 ? null : () => Navigator.pop(dialog, true),
              child: const Text('Cancel the ID'),
            ),
          ],
        ),
      ),
    );
    // Not disposed here: the dialog may still be closing; the controller goes with this call.
    final text = reason.text.trim();
    if (go == true && context.mounted) await _decide(context, 'cancelFieldStaff', {'staffUid': staffUid, 'reason': text});
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
          if ('${data['pincode'] ?? ''}'.isNotEmpty) Text('Registered at: ${[data['town'], data['pincode']].where((v) => '${v ?? ''}'.isNotEmpty).join(' ')}'),
          if ('${data['gpsAddress'] ?? ''}'.isNotEmpty) Text('Area from GPS: ${data['gpsAddress']}'),
          if (data['latitude'] is num && data['longitude'] is num)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ShopMap(shops: [Entry(staffUid, {'name': name, 'latitude': data['latitude'], 'longitude': data['longitude']})], height: 180),
              ),
            ),
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
          if (status == 'cancelled')
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Status: Cancelled for good', key: ValueKey('staff-cancelled'), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              if ('${data['cancelReason'] ?? ''}'.isNotEmpty) Text('Reason: ${data['cancelReason']}'),
              const Text('This ID is closed and never given again. A new staff member gets a new ID.'),
            ])))
          else if (!pending) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Status: ${suspended ? 'Suspended' : status}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (suspended && (data['decisionReason'] ?? '').toString().trim().isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('Reason: ${data['decisionReason']}')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              suspended
                  ? FilledButton(onPressed: () => _setSuspension(context, name, suspend: false), child: const Text('Reinstate'))
                  : FilledButton.tonal(onPressed: () => _setSuspension(context, name, suspend: true), child: const Text('Suspend')),
              OutlinedButton(
                key: const ValueKey('staff-cancel-id'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => _cancel(context, code ?? staffUid),
                child: const Text('Cancel staff ID'),
              ),
            ]),
          ]))),
        ]);
        },
      ),
    ),
  );
}
