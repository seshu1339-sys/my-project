import 'package:flutter/material.dart';

import 'admin_frame.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'admin_staff_additions.dart';
import 'moderation_dialogs.dart';
import 'photo_check.dart';
import 'staff_auto_approve_switch.dart';
import 'shop_map.dart';

/// Field Assistant approvals — a separate admin tool from Vendor moderation,
/// its own page reached via its own nav button. Never mixed into the vendor
/// queues: a pending field-staff request and a pending field submission each
/// get their own section here, nowhere near vendorApplications/vendorChanges.
class FieldModerationPage extends StatelessWidget {
  const FieldModerationPage({super.key, required this.store});
  final Store store;

  Future<void> decide(BuildContext context, String function, Map<String, dynamic> data) =>
      runModerationAction(context, () => store.call(function, data), onSuccess: (_) => 'Decision saved');

  Future<void> _reviewStaff(BuildContext context, String staffUid, {required bool approved}) async {
    var reason = '';
    if (!approved) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
        title: const Text('Reject field staff request'),
        content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason (optional)')),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Reject'))],
      ));
      reason = controller.text.trim();
      controller.dispose();
      if (ok != true) return;
    }
    if (!context.mounted) return;
    await decide(context, 'reviewFieldStaff', {'staffUid': staffUid, 'approved': approved, 'reason': reason});
  }

  Future<void> _setSuspension(BuildContext context, String staffUid, String name, {required bool suspend}) async {
    final reason = await showSuspensionDialog(
      context,
      name: name,
      suspend: suspend,
      suspendBody: 'They will not be able to submit new entries until reinstated.',
      reinstateBody: 'They will be able to submit entries again.',
    );
    if (reason == null || !context.mounted) return;
    await decide(context, 'setFieldStaffSuspension', {'staffUid': staffUid, 'suspended': suspend, 'reason': reason});
  }

  Future<void> _reviewEntry(BuildContext context, String entryId, {required bool approved}) async {
    var reason = '';
    if (!approved) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
        title: const Text('Reject field entry'),
        content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason (shown to the staff member)')),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Reject'))],
      ));
      reason = controller.text.trim();
      controller.dispose();
      if (ok != true) return;
    }
    if (!context.mounted) return;
    await decide(context, 'reviewFieldEntry', {'entryId': entryId, 'approved': approved, 'reason': reason});
  }

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    title: 'Field Assistant approvals',
    body: ListView(padding: const EdgeInsets.all(20), children: [
      // Vendors and service providers that staff added (Staff > Add): reviewed with a Google check of every photo.
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('staffAdditions').where('status', isEqualTo: 'pending').limit(100).snapshots(),
        builder: (context, snapshot) => Card(
          child: ListTile(
            key: const ValueKey('open-staff-additions'),
            leading: const Icon(Icons.add_business_outlined),
            title: const Text('Vendors and services added by staff'),
            subtitle: Text(snapshot.hasError ? 'Could not load.' : '${snapshot.data?.size ?? 0} waiting for approval'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StaffAdditionsReviewPage(store: store))),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text('Pending field staff', style: Theme.of(context).textTheme.titleLarge),
      const Text('Anyone who signs into the Field Assistant app appears here first — nothing else is possible until approved.'),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldStaff').where('status', isEqualTo: 'pending').limit(100).snapshots(),
        builder: (context, snapshot) => Column(children: [
          if (snapshot.hasError) const ListTile(title: Text('Pending field staff could not load.')),
          for (final doc in snapshot.data?.docs ?? const []) _staffTile(context, doc, pending: true),
          if (snapshot.hasData && snapshot.data!.docs.isEmpty) const ListTile(title: Text('No pending field staff requests.')),
        ]),
      ),
      const SizedBox(height: 24),
      Text('Active and suspended field staff', style: Theme.of(context).textTheme.titleLarge),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldStaff').where('status', whereIn: ['active', 'suspended']).limit(200).snapshots(),
        builder: (context, snapshot) => Column(children: [
          if (snapshot.hasError) const ListTile(title: Text('Field staff could not load.')),
          for (final doc in snapshot.data?.docs ?? const []) _staffTile(context, doc, pending: false),
          if (snapshot.hasData && snapshot.data!.docs.isEmpty) const ListTile(title: Text('No active field staff yet.')),
        ]),
      ),
      const SizedBox(height: 24),
      Text('Pending field submissions', style: Theme.of(context).textTheme.titleLarge),
      const Text('A new shop or product only appears to customers once approved here.'),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldSubmissions').where('status', isEqualTo: 'pending').limit(100).snapshots(),
        builder: (context, snapshot) => Column(children: [
          if (snapshot.hasError) const ListTile(title: Text('Pending field submissions could not load.')),
          for (final doc in snapshot.data?.docs ?? const []) _submissionTile(context, doc),
          if (snapshot.hasData && snapshot.data!.docs.isEmpty) const ListTile(title: Text('No pending field submissions.')),
        ]),
      ),
    ]),
  );

  Widget _staffTile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc, {required bool pending}) {
    final data = doc.data();
    final name = data['name']?.toString().isNotEmpty == true ? data['name'].toString() : doc.id;
    final email = data['email']?.toString() ?? '';
    // Staff ID, phone and where they registered (staff who registered before the location was required have no place).
    final place = [data['town'], data['pincode']].where((v) => '${v ?? ''}'.isNotEmpty).join(' ');
    final details = [
      if ('${data['staffCode'] ?? ''}'.isNotEmpty) 'Staff ID: ${data['staffCode']}',
      if ('${data['phone'] ?? ''}'.isNotEmpty) 'Phone: ${data['phone']}',
      if (place.isNotEmpty) 'Registered at: $place',
    ].join(' • ');
    if (pending) {
      return Card(child: ListTile(
        key: ValueKey('pending-staff-${doc.id}'),
        title: Text(name),
        subtitle: Text([email, if (details.isNotEmpty) details].join('\n')),
        isThreeLine: details.isNotEmpty,
        trailing: Wrap(children: [
          IconButton(tooltip: 'Approve', onPressed: () => _reviewStaff(context, doc.id, approved: true), icon: const Icon(Icons.check)),
          IconButton(tooltip: 'Reject', onPressed: () => _reviewStaff(context, doc.id, approved: false), icon: const Icon(Icons.close)),
        ]),
      ));
    }
    final status = data['status']?.toString() ?? '';
    final suspended = status == 'suspended';
    final reason = data['decisionReason']?.toString() ?? '';
    return Card(child: Column(children: [
      ListTile(
        title: Text(name),
        subtitle: Text('$email • ${suspended ? 'Suspended${reason.isEmpty ? '' : ' — $reason'}' : 'Active'}${details.isEmpty ? '' : '\n$details'}'),
        isThreeLine: details.isNotEmpty,
        trailing: suspended
            ? OutlinedButton(onPressed: () => _setSuspension(context, doc.id, name, suspend: false), child: const Text('Reinstate'))
            : FilledButton.tonal(onPressed: () => _setSuspension(context, doc.id, name, suspend: true), child: const Text('Suspend')),
      ),
      // Trusted staff: what they add goes live without approval (off by default).
      if (!suspended)
        StaffAutoApproveSwitch(
          key: ValueKey('auto-approve-${doc.id}'),
          staffName: name,
          value: data['autoApprove'] == true,
          onChanged: (enabled) => store.call('setStaffAutoApprove', {'staffUid': doc.id, 'enabled': enabled}),
        ),
    ]));
  }

  Widget _submissionTile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final item = data['item'] as Map<String, dynamic>? ?? const {};
    final shop = data['shop'] as Map<String, dynamic>?;
    final shopId = data['shopId']?.toString() ?? '';
    final visitLat = data['visitLatitude'], visitLng = data['visitLongitude'];
    return Card(child: ExpansionTile(
      title: Text('${item['name']}'),
      subtitle: Text('${data['staffName'] ?? data['staffUid']} • ₹${item['price']} • Stock ${item['stock']}'),
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Wrap(spacing: 12, runSpacing: 12, children: [
          for (final p in (item['photoPaths'] as List? ?? const []))
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ApplicationPhoto(path: p?.toString(), height: 150, width: 200), PhotoCheck(store: store, path: '$p')]),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(
          shopId.isNotEmpty ? 'Existing shop: $shopId' : 'New shop: ${shop?['name']} • ${shop?['address']} • ${shop?['pincode']}',
        )),
        if (visitLat is num && visitLng is num)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Staff location at submission', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(
              shops: [Entry(doc.id, {'name': '${item['name']}', 'latitude': visitLat, 'longitude': visitLng})],
              height: 200,
            )),
          ])),
        OverflowBar(children: [
          IconButton(tooltip: 'Approve', onPressed: () => _reviewEntry(context, doc.id, approved: true), icon: const Icon(Icons.check)),
          IconButton(tooltip: 'Reject', onPressed: () => _reviewEntry(context, doc.id, approved: false), icon: const Icon(Icons.close)),
        ]),
      ],
    ));
  }
}
