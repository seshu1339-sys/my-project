import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/shop_ads.dart';
import '../domain/vendor_items.dart';
import 'moderation_dialogs.dart';
import 'shop_map.dart';
import 'text_prompt_dialog.dart';

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

  Future<void> _decide(BuildContext context, String function, Map<String, dynamic> data) =>
      runModerationAction(context, () => store.call(function, data));

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
                  // "Ad for your shop" ticked in the vendor app: the ad is arranged in Settings > Right Side Ad Boxes.
                  if (vendor['adInterest'] == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Wants an ad for their shop${shopAdTime(vendor['adInterestAt']) == null ? '' : ' (ticked ${shopAdDate(shopAdTime(vendor['adInterestAt']))})'}. Link a box to them in Settings > Right Side Ad Boxes.', key: const ValueKey('vendor-wants-ad')),
                    ),
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
                  const SizedBox(height: 16),
                  VendorItemsAdminCard(store: store, vendorUid: vendorUid, itemLimit: vendorItemLimit(vendor)),
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

/// The vendor's own items, live or hidden, with a switch to hide or show each, and how many items the vendor may have (2 unless the
/// admin allows more; items hidden here still count).
class VendorItemsAdminCard extends StatelessWidget {
  const VendorItemsAdminCard({super.key, required this.store, required this.vendorUid, required this.itemLimit});
  final Store store;
  final String vendorUid;
  final int itemLimit;

  Future<void> _changeLimit(BuildContext context) async {
    final text = await askText(context, title: 'Items this vendor may have', label: 'Number of items (0-100)', helper: 'Items you hide still count.', initial: '$itemLimit', keyboardType: TextInputType.number, fieldKey: const ValueKey('vendor-item-limit-field'));
    final value = int.tryParse(text ?? '');
    if (value == null || !context.mounted) return;
    try {
      await store.call('setVendorItemLimit', {'vendorId': vendorUid, 'itemLimit': value});
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('This vendor may now have $value item${value == 1 ? '' : 's'}.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('products').where('ownerId', isEqualTo: vendorUid).snapshots(),
    builder: (context, snapshot) {
      final items = snapshot.data?.docs ?? const [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Items: ${items.length} of $itemLimit allowed', style: const TextStyle(fontWeight: FontWeight.bold))),
              OutlinedButton(key: const ValueKey('vendor-item-limit'), onPressed: () => _changeLimit(context), child: const Text('Change limit')),
            ],
          ),
          if (items.isEmpty) const Text('No items yet.'),
          for (final doc in items)
            SwitchListTile(
              key: ValueKey('vendor-item-${doc.id}'),
              contentPadding: EdgeInsets.zero,
              secondary: '${doc.data()['imageUrl'] ?? ''}'.isEmpty
                  ? const Icon(Icons.inventory_2_outlined)
                  : SizedBox(width: 40, height: 40, child: Image.network('${doc.data()['imageUrl']}', fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined))),
              title: Text('${doc.data()['name'] ?? doc.id}'),
              subtitle: Text('${vendorPriceLine(doc.data(), DateTime.now())} • ${doc.data()['active'] == false ? 'Hidden' : 'Live'}'),
              value: doc.data()['active'] != false,
              onChanged: (live) => store.updateFields('products', doc.id, {'active': live}),
            ),
        ],
      );
    },
  );
}
