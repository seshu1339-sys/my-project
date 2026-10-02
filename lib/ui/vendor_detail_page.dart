import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'moderation_dialogs.dart';
import 'shop_map.dart';

/// One vendor's full admin profile, reached from the unified admin search
/// (admin_search.dart). Consolidates the same per-vendor controls
/// VendorModerationPage already exposes inline in its long list — application
/// decision, fee confirmation, suspension, Special Category Exclusives, and the
/// verified shop location — calling the exact same existing Cloud Functions.
/// vendor_moderation.dart itself is not touched; this is a new, independent view.
/// Also shows what that inline list leaves out: the two application photos,
/// contact details, the vendor's linked shop record, and any of its pending
/// vendorChanges submissions.
class VendorDetailPage extends StatelessWidget {
  const VendorDetailPage({super.key, required this.store, required this.vendorUid});
  final Store store;
  final String vendorUid;

  Future<void> _decide(BuildContext context, String function, Map<String, dynamic> data) async {
    try {
      await FirebaseFunctions.instance.httpsCallable(function).call(data);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _setSuspension(BuildContext context, String name, {required bool suspend}) async {
    final reason = await showSuspensionDialog(
      context,
      name: name,
      suspend: suspend,
      suspendBody: 'The vendor is locked out immediately and its shop and products are hidden from customers. The vendor sees the reason below.',
      reinstateBody: 'The vendor can trade again and the shop and products hidden by the suspension are shown to customers again.',
    );
    if (reason == null || !context.mounted) return;
    await _decide(context, 'setVendorSuspension', {'vendorId': vendorUid, 'suspended': suspend, 'reason': reason});
  }

  Future<void> _setExclusives(BuildContext context, String name, {required bool currentlyEnabled, int? currentMaxDays}) async {
    final result = await showExclusivesDialog(context, name: name, currentlyEnabled: currentlyEnabled, currentMaxDays: currentMaxDays);
    if (result == null || !context.mounted) return;
    await _decide(context, 'setVendorExclusivesPermission', {'vendorId': vendorUid, 'enabled': result.enabled, if (result.enabled) 'maxDurationDays': result.maxDurationDays});
  }

  Future<void> _confirmFee(BuildContext context, {required bool paid}) =>
      _decide(context, 'confirmVendorFeePayment', {'vendorId': vendorUid, 'paid': paid});

  Future<void> _reviewApplication(BuildContext context, {required bool approved}) =>
      _decide(context, 'approveVendor', {'vendorId': vendorUid, 'approved': approved, 'feeRequired': false, 'feeAmount': 0, 'reason': ''});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vendor profile')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('vendorApplications').doc(vendorUid).snapshots(),
      builder: (context, appSnapshot) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('vendors').doc(vendorUid).snapshots(),
        builder: (context, vendorSnapshot) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          // A vendor's shop document id is always its own uid (see approveVendor
          // in functions/index.js: `shopId: vendorId`).
          stream: store.firestore.collection('shops').doc(vendorUid).snapshots(),
          builder: (context, shopSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: store.firestore.collection('vendorChanges').where('vendorId', isEqualTo: vendorUid).where('status', isEqualTo: 'pending').limit(50).snapshots(),
            builder: (context, pendingSnapshot) {
              final application = appSnapshot.data?.data();
              final vendor = vendorSnapshot.data?.data();
              final shop = shopSnapshot.data?.data();
              final pending = pendingSnapshot.data?.docs ?? const [];
              if (application == null && vendor == null) {
                return const Center(child: Text('This vendor record could not be found.'));
              }
              final name = (vendor?['name'] ?? application?['name'] ?? vendorUid).toString();
              final code = vendor?['vendorCode'] as String?;
              final appStatus = application?['status']?.toString();
              final suspended = vendor?['status'] == 'suspended';
              final exclusives = vendor?['specialCategoryExclusives'] == true;
              return ListView(padding: const EdgeInsets.all(20), children: [
                Text(name, style: Theme.of(context).textTheme.headlineSmall),
                if (code != null) Text('Vendor ID: $code', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('UID: $vendorUid', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                if (application != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Photos', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 16, runSpacing: 12, children: [
                    ApplicationPhoto(label: 'Vendor photo', path: application['vendorPhotoPath']?.toString()),
                    ApplicationPhoto(label: 'Shop photo', path: application['shopPhotoPath']?.toString()),
                  ]),
                  const SizedBox(height: 16),
                  const Text('Contact details', style: TextStyle(fontWeight: FontWeight.bold)),
                  if ((application['ownerName'] ?? '').toString().isNotEmpty) Text('Owner: ${application['ownerName']}'),
                  if ((application['phone'] ?? '').toString().isNotEmpty) Text('Phone: ${application['phone']}'),
                  if ((application['address'] ?? '').toString().isNotEmpty) Text('Address: ${application['address']} ${application['pincode'] ?? ''}'),
                  if ((application['shopCategory'] ?? '').toString().isNotEmpty) Text('Category: ${application['shopCategory']}'),
                  if ((application['description'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${application['description']}')),
                ]))),
                const SizedBox(height: 16),
                if (shop != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Linked shop', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${shop['name'] ?? vendorUid}'),
                  if ((shop['address'] ?? '').toString().isNotEmpty) Text('${shop['address']}'),
                  Text('Visible to customers: ${shop['active'] == true ? 'Yes' : 'No'}'),
                ]))),
                const SizedBox(height: 16),
                if (pending.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.pending_actions, size: 18),
                    const SizedBox(width: 8),
                    Text('Pending submissions (${pending.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  for (final doc in pending) Padding(padding: const EdgeInsets.only(top: 8), child: Text(
                    '• ${doc.data()['type']} on ${doc.data()['collection']}/${doc.data()['docId']} — ${doc.data()['newValue']?['name'] ?? doc.data()['newValue']}',
                  )),
                ]))),
                const SizedBox(height: 16),
                if (appStatus == 'pending') Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Application pending approval', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  OverflowBar(children: [
                    FilledButton(onPressed: () => _reviewApplication(context, approved: true), child: const Text('Approve')),
                    OutlinedButton(onPressed: () => _reviewApplication(context, approved: false), child: const Text('Reject')),
                  ]),
                ]))),
                if (appStatus == 'payment_submitted') Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Fee payment awaiting confirmation — reference: ${application?['paymentReference']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  OverflowBar(children: [
                    FilledButton(onPressed: () => _confirmFee(context, paid: true), child: const Text('Confirm paid')),
                    OutlinedButton(onPressed: () => _confirmFee(context, paid: false), child: const Text('Reject payment')),
                  ]),
                ]))),
                if (vendor != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Status: ${suspended ? 'Suspended' : vendor['status']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (suspended && (vendor['suspensionReason'] ?? '').toString().trim().isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('Reason: ${vendor['suspensionReason']}')),
                  const SizedBox(height: 12),
                  OverflowBar(children: [
                    suspended
                        ? FilledButton(onPressed: () => _setSuspension(context, name, suspend: false), child: const Text('Reinstate'))
                        : FilledButton.tonal(onPressed: () => _setSuspension(context, name, suspend: true), child: const Text('Suspend')),
                    OutlinedButton(
                      onPressed: () => _setExclusives(context, name, currentlyEnabled: exclusives, currentMaxDays: (vendor['exclusivesMaxDurationDays'] as num?)?.toInt()),
                      child: Text(exclusives ? 'Exclusives: on (up to ${vendor['exclusivesMaxDurationDays']}d)' : 'Exclusives: off'),
                    ),
                  ]),
                  if (vendor['latitude'] is num && vendor['longitude'] is num) Padding(padding: const EdgeInsets.only(top: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Verified shop location', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(
                      shops: [Entry(vendorUid, {'name': name, 'latitude': vendor['latitude'], 'longitude': vendor['longitude']})],
                      height: 220,
                    )),
                  ])),
                ]))),
              ]);
            },
          ),
        ),
      ),
    ),
  );
}
