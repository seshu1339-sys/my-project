import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'shop_map.dart';

/// Field Assistant approvals — a separate admin tool from Vendor moderation,
/// its own page reached via its own nav button. Never mixed into the vendor
/// queues: a pending field-staff request and a pending field submission each
/// get their own section here, nowhere near vendorApplications/vendorChanges.
class FieldModerationPage extends StatelessWidget {
  const FieldModerationPage({super.key, required this.store});
  final Store store;

  Future<void> decide(BuildContext context, String function, Map<String, dynamic> data) async {
    try {
      await FirebaseFunctions.instance.httpsCallable(function).call(data);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decision saved')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

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
    final reason = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (dialog) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(suspend ? 'Suspend $name?' : 'Reinstate $name?'),
      content: suspend
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('They will not be able to submit new entries until reinstated.'),
              TextField(controller: reason, maxLines: 3, maxLength: 500, onChanged: (_) => setDialogState(() {}), decoration: const InputDecoration(labelText: 'Reason for suspension (required)')),
            ])
          : const Text('They will be able to submit entries again.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(onPressed: suspend && reason.text.trim().length < 3 ? null : () => Navigator.pop(dialog, true), child: Text(suspend ? 'Suspend' : 'Reinstate')),
      ],
    )));
    final note = reason.text.trim();
    reason.dispose();
    if (go != true || !context.mounted) return;
    await decide(context, 'setFieldStaffSuspension', {'staffUid': staffUid, 'suspended': suspend, 'reason': note});
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Field Assistant approvals')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
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
    if (pending) {
      return Card(child: ListTile(
        title: Text(name),
        subtitle: Text(email),
        trailing: Wrap(children: [
          IconButton(tooltip: 'Approve', onPressed: () => _reviewStaff(context, doc.id, approved: true), icon: const Icon(Icons.check)),
          IconButton(tooltip: 'Reject', onPressed: () => _reviewStaff(context, doc.id, approved: false), icon: const Icon(Icons.close)),
        ]),
      ));
    }
    final status = data['status']?.toString() ?? '';
    final suspended = status == 'suspended';
    final reason = data['decisionReason']?.toString() ?? '';
    return Card(child: ListTile(
      title: Text(name),
      subtitle: Text('$email • ${suspended ? 'Suspended${reason.isEmpty ? '' : ' — $reason'}' : 'Active'}'),
      trailing: suspended
          ? OutlinedButton(onPressed: () => _setSuspension(context, doc.id, name, suspend: false), child: const Text('Reinstate'))
          : FilledButton.tonal(onPressed: () => _setSuspension(context, doc.id, name, suspend: true), child: const Text('Suspend')),
    ));
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
          for (final p in (item['photoPaths'] as List? ?? const [])) _FieldPhoto(path: p?.toString()),
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

/// One private field-submission photo, fetched with the admin's own Storage
/// access. Mirrors admin.dart's _ApplicationPhoto exactly but stays local to
/// this file so Field Assistant moderation never depends on vendor code.
class _FieldPhoto extends StatelessWidget {
  const _FieldPhoto({required this.path});
  final String? path;
  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return Container(height: 150, width: 200, alignment: Alignment.center, color: Colors.black12, child: const Text('Photo missing'));
    }
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(path!).getDownloadURL(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Container(height: 150, width: 200, alignment: Alignment.center, color: Colors.black12, child: const Text('Photo could not load'));
        if (!snapshot.hasData) return const SizedBox(height: 150, width: 200, child: Center(child: CircularProgressIndicator()));
        final url = snapshot.data!;
        return Semantics(button: true, label: 'View item photo full size', child: InkWell(
          onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url)))),
          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, height: 150, width: 200, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(height: 150, width: 200, alignment: Alignment.center, color: Colors.black12, child: const Text('Photo could not load')))),
        ));
      },
    );
  }
}
