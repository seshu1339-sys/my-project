import 'package:flutter/material.dart';

import 'admin_frame.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'moderation_dialogs.dart';
import 'shop_map.dart';

/// Vendor applications, fee payments, active/suspended vendors, pending shop
/// photos, and pending public changes — all vendor-moderation concerns in
/// one self-contained page, independent of the generic EntryEditor/admin
/// shell (admin.dart) and the other moderation pages in this app.
class VendorModerationPage extends StatelessWidget {
  const VendorModerationPage({super.key, required this.store});
  final Store store;
  Future<void> decide(BuildContext context, String function, Map<String, dynamic> data) =>
      runModerationAction(context, () => store.call(function, data), onSuccess: (_) => 'Decision saved');
  Future<void> reviewApplication(BuildContext context, String vendorId, {required bool approved}) async {
    var feeRequired = false;
    final amount = TextEditingController(text: '500');
    final reason = TextEditingController();
    final submit = await showDialog<bool>(context: context, builder: (dialog) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(approved ? 'Review vendor application' : 'Reject vendor application'),
      content: approved ? Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(title: const Text('Fee required'), value: feeRequired, onChanged: (value) => setDialogState(() => feeRequired = value)),
        if (feeRequired) TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Custom vendor fee amount', helperText: 'Any amount, for example 1000. Enter 0 for no payment.')),
        TextField(controller: reason, decoration: const InputDecoration(labelText: 'Review note (optional)')),
      ]) : TextField(controller: reason, maxLines: 3, decoration: const InputDecoration(labelText: 'Rejection reason')),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(approved ? 'Save review' : 'Reject'))],
    )));
    if (submit != true) { amount.dispose(); reason.dispose(); return; }
    if (!context.mounted) { amount.dispose(); reason.dispose(); return; }
    // ₹0 means no payment, so a blank or unreadable amount must never be treated as 0.
    final feeAmount = double.tryParse(amount.text.trim());
    if (approved && feeRequired && (feeAmount == null || feeAmount < 0)) {
      amount.dispose(); reason.dispose();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid fee amount, for example 1000. Enter 0 for no payment.')));
      return;
    }
    await decide(context, 'approveVendor', {'vendorId': vendorId, 'approved': approved, 'feeRequired': approved && feeRequired, 'feeAmount': approved && feeRequired ? feeAmount : 0, 'reason': reason.text.trim()});
    amount.dispose(); reason.dispose();
  }
  @override
  Widget build(BuildContext context) => AdminPageFrame(
        title: 'Vendor approvals and publishing',
        actions: [
          TextButton.icon(onPressed: () => _verifyShop(context), icon: const Icon(Icons.location_on), label: const Text('Verify shop')),
        ],
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Vendor applications', style: Theme.of(context).textTheme.titleLarge),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: store.firestore.collection('vendorApplications').where('status', isEqualTo: 'pending').limit(100).snapshots(),
            builder: (context, snapshot) => Column(children: [
              if (snapshot.hasError) const ListTile(title: Text('Vendor applications could not load.')),
              for (final doc in snapshot.data?.docs ?? const []) _applicationTile(context, doc),
              if (snapshot.hasData && snapshot.data!.docs.isEmpty) const ListTile(title: Text('No pending applications.')),
            ]),
          ),
          const SizedBox(height: 16),
          Text('Vendor fee payments awaiting confirmation', style: Theme.of(context).textTheme.titleLarge),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: store.firestore.collection('vendorApplications').where('status', isEqualTo: 'payment_submitted').limit(100).snapshots(),
            builder: (context, snapshot) => Column(children: [
              if (snapshot.hasError) const ListTile(title: Text('Vendor fee payments could not load.')),
              for (final doc in snapshot.data?.docs ?? const []) Card(child: ListTile(
                title: Text(doc.data()['name']?.toString() ?? doc.id),
                subtitle: Text('Amount: ${doc.data()['feeAmount']} • Reference: ${doc.data()['paymentReference']}'),
                trailing: Wrap(children: [
                  IconButton(tooltip: 'Confirm paid', onPressed: () => decide(context, 'confirmVendorFeePayment', {'vendorId': doc.id, 'paid': true}), icon: const Icon(Icons.check)),
                  IconButton(tooltip: 'Reject payment', onPressed: () => decide(context, 'confirmVendorFeePayment', {'vendorId': doc.id, 'paid': false}), icon: const Icon(Icons.close)),
                ]),
              )),
              if (snapshot.hasData && snapshot.data!.docs.isEmpty) const ListTile(title: Text('No vendor fee payments awaiting confirmation.')),
            ]),
          ),
          const SizedBox(height: 24),
          Text('Active and suspended vendors', style: Theme.of(context).textTheme.titleLarge),
          const Text('Suspending a vendor stops all its business actions at once and hides its shop and products from customers. Reinstating restores everything.'),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: store.firestore.collection('vendors').where('status', whereIn: ['approved', 'suspended']).limit(200).snapshots(),
            builder: (context, snapshot) => Column(children: [
              if (snapshot.hasError) const ListTile(title: Text('Vendors could not load.')),
              for (final doc in snapshot.data?.docs ?? const []) _vendorTile(context, doc),
              if (snapshot.hasData && snapshot.data!.docs.isEmpty) const ListTile(title: Text('No approved vendors yet.')),
            ]),
          ),
          const SizedBox(height: 24),
          Text('Pending shop photos', style: Theme.of(context).textTheme.titleLarge),
          Text('Each vendor may upload up to ${store.business.number('vendorPhotoLimit', 3).round().clamp(1, 9)} shop photos. A photo stays hidden from customers until approved here, and is deleted automatically if left unreviewed for 15 days.'),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: store.firestore.collection('vendorShopPhotos').where('status', isEqualTo: 'pending').limit(100).snapshots(),
            builder: (context, snapshot) => Column(children: [
              if (snapshot.hasError) const ListTile(title: Text('Pending shop photos could not load.')),
              for (final doc in snapshot.data?.docs ?? const []) _shopPhotoTile(context, doc),
              if (snapshot.hasData && snapshot.data!.docs.isEmpty) const ListTile(title: Text('No pending shop photos.')),
            ]),
          ),
          const SizedBox(height: 24),
          Text('Pending public changes', style: Theme.of(context).textTheme.titleLarge),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: store.firestore.collection('vendorChanges').where('status', isEqualTo: 'pending').limit(100).snapshots(),
            builder: (context, snapshot) => Column(children: [
              if (snapshot.hasError) const ListTile(title: Text('Pending changes could not load.')),
              for (final doc in snapshot.data?.docs ?? const []) _changeTile(context, doc),
              if (snapshot.hasData && snapshot.data!.docs.isEmpty) const ListTile(title: Text('No pending changes.')),
            ]),
          ),
          const SizedBox(height: 24),
          const Text('The Business profile editor controls Auto-publish vendor changes. Rejected changes remain unpublished and their reason is visible to the vendor.'),
        ]),
      );
  Future<void> _verifyShop(BuildContext context) async {
    final vendor = TextEditingController(), shop = TextEditingController(), latitude = TextEditingController(), longitude = TextEditingController(), radius = TextEditingController(text: '1');
    final submit = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Verify vendor shop location'),
      content: SingleChildScrollView(child: Column(children: [
        TextField(controller: vendor, decoration: const InputDecoration(labelText: 'Vendor ID')),
        TextField(controller: shop, decoration: const InputDecoration(labelText: 'Shop ID')),
        TextField(controller: latitude, decoration: const InputDecoration(labelText: 'Latitude')),
        TextField(controller: longitude, decoration: const InputDecoration(labelText: 'Longitude')),
        TextField(controller: radius, decoration: const InputDecoration(labelText: 'Radius in km')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Verify'))],
    ));
    if (submit != true || !context.mounted) return;
    await runModerationAction(
      context,
      () => store.call('verifyVendorShop', {'vendorId': vendor.text.trim(), 'shopId': shop.text.trim(), 'latitude': double.parse(latitude.text), 'longitude': double.parse(longitude.text), 'radiusKm': double.parse(radius.text)}),
      onSuccess: (_) => 'Shop verified',
    );
  }
  Widget _applicationTile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Card(child: ExpansionTile(
      title: Text(data['name']?.toString() ?? doc.id),
      subtitle: Text('Vendor ID: ${data['vendorCode'] ?? doc.id} • ${data['status'] == 'pending' ? 'Pending Approval' : data['status']}'),
      children: [
        // The two mandatory photos are stored separately; both are shown for review.
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Wrap(spacing: 16, runSpacing: 12, children: [
          ApplicationPhoto(label: 'Vendor photo', path: data['vendorPhotoPath']?.toString(), height: 150, width: 200),
          ApplicationPhoto(label: 'Shop photo', path: data['shopPhotoPath']?.toString(), height: 150, width: 200),
        ])),
        if (data['latitude'] is num && data['longitude'] is num)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Shop location captured at registration', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(
              shops: [Entry(doc.id, {'name': data['name'] ?? doc.id, 'latitude': data['latitude'], 'longitude': data['longitude']})],
              height: 200,
            )),
          ])),
        for (final entry in data.entries.where((e) => e.key != 'vendorPhotoPath' && e.key != 'shopPhotoPath')) ListTile(dense: true, title: Text(entry.key), subtitle: Text('${entry.value}')),
        OverflowBar(children: [
          IconButton(tooltip: 'Approve', onPressed: () => reviewApplication(context, doc.id, approved: true), icon: const Icon(Icons.check)),
          IconButton(tooltip: 'Reject', onPressed: () => reviewApplication(context, doc.id, approved: false), icon: const Icon(Icons.close)),
        ]),
      ],
    ));
  }
  Future<void> _setSuspension(BuildContext context, String vendorId, String name, {required bool suspend}) async {
    final reason = await showSuspensionDialog(
      context,
      name: name,
      suspend: suspend,
      suspendBody: 'The vendor is locked out immediately and its shop and products are hidden from customers. The vendor sees the reason below.',
      reinstateBody: 'The vendor can trade again and the shop and products hidden by the suspension are shown to customers again.',
    );
    if (reason == null || !context.mounted) return;
    await runModerationAction(
      context,
      () => store.call('setVendorSuspension', {'vendorId': vendorId, 'suspended': suspend, 'reason': reason}),
      onSuccess: (result) => suspend
          ? '$name suspended. ${result['itemsChanged']} item(s) hidden from customers.'
          : '$name reinstated. ${result['itemsChanged']} item(s) shown again.',
    );
  }
  Widget _vendorTile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final suspended = data['status'] == 'suspended';
    final name = data['name']?.toString() ?? doc.id;
    final reason = '${data['suspensionReason'] ?? ''}'.trim();
    final exclusives = data['specialCategoryExclusives'] == true;
    return Card(child: ListTile(
      title: Text(name),
      subtitle: Text('Vendor ID: ${data['vendorCode'] ?? doc.id} • ${suspended ? 'Suspended${reason.isEmpty ? '' : ' — $reason'}' : 'Active'}'
          '${exclusives ? ' • Exclusives up to ${data['exclusivesMaxDurationDays']} day(s)' : ''}'),
      trailing: Wrap(spacing: 8, children: [
        if (data['latitude'] is num && data['longitude'] is num)
          IconButton(tooltip: 'View shop location', icon: const Icon(Icons.map_outlined), onPressed: () => showDialog<void>(context: context, builder: (_) => Dialog(child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ShopMap(shops: [Entry(doc.id, {'name': name, 'latitude': data['latitude'], 'longitude': data['longitude']})], height: 260),
          ]))))),
        ),
        OutlinedButton(onPressed: () => _setExclusivesPermission(context, doc.id, name, currentlyEnabled: exclusives, currentMaxDays: (data['exclusivesMaxDurationDays'] as num?)?.toInt()), child: Text(exclusives ? 'Exclusives: on' : 'Exclusives: off')),
        suspended
            ? OutlinedButton(onPressed: () => _setSuspension(context, doc.id, name, suspend: false), child: const Text('Reinstate'))
            : FilledButton.tonal(onPressed: () => _setSuspension(context, doc.id, name, suspend: true), child: const Text('Suspend')),
      ]),
    ));
  }
  Future<void> _setExclusivesPermission(BuildContext context, String vendorId, String name, {required bool currentlyEnabled, int? currentMaxDays}) async {
    final result = await showExclusivesDialog(context, name: name, currentlyEnabled: currentlyEnabled, currentMaxDays: currentMaxDays);
    if (result == null || !context.mounted) return;
    await runModerationAction(
      context,
      () => store.call('setVendorExclusivesPermission', {'vendorId': vendorId, 'enabled': result.enabled, if (result.enabled) 'maxDurationDays': result.maxDurationDays}),
      onSuccess: (_) => result.enabled ? 'Exclusives enabled for $name (up to ${result.maxDurationDays} day(s))' : 'Exclusives disabled for $name',
    );
  }
  Widget _shopPhotoTile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Card(child: ListTile(
      leading: ApplicationPhoto(label: 'Slot ${data['slot']}', path: data['path']?.toString(), height: 150, width: 200),
      title: Text('${data['vendorName'] ?? data['vendorId']}'),
      subtitle: Text('Shop photo, slot ${data['slot']}'),
      trailing: Wrap(children: [
        IconButton(tooltip: 'Approve', onPressed: () => _reviewShopPhoto(context, data['vendorId'].toString(), (data['slot'] as num).toInt(), approved: true), icon: const Icon(Icons.check)),
        IconButton(tooltip: 'Reject', onPressed: () => _reviewShopPhoto(context, data['vendorId'].toString(), (data['slot'] as num).toInt(), approved: false), icon: const Icon(Icons.close)),
      ]),
    ));
  }
  Future<void> _reviewShopPhoto(BuildContext context, String vendorId, int slot, {required bool approved}) async {
    var reason = '';
    if (!approved) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
        title: const Text('Reject shop photo'),
        content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason (shown to the vendor)')),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Reject'))],
      ));
      reason = controller.text.trim();
      controller.dispose();
      if (ok != true) return;
    }
    if (!context.mounted) return;
    await decide(context, 'reviewShopPhoto', {'vendorId': vendorId, 'slot': slot, 'approved': approved, 'reason': reason});
  }
  Widget _changeTile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Card(child: ListTile(
      title: Text('${data['vendorName'] ?? data['vendorId']} • ${data['type']}'),
      subtitle: Text('${data['collection']}/${data['docId']}\nOld: ${data['oldValue']}\nNew: ${data['newValue']}'),
      isThreeLine: true,
      trailing: Wrap(children: [
        IconButton(tooltip: 'Approve', onPressed: () => decide(context, 'reviewVendorChange', {'changeId': doc.id, 'approved': true}), icon: const Icon(Icons.check)),
        IconButton(tooltip: 'Reject', onPressed: () => decide(context, 'reviewVendorChange', {'changeId': doc.id, 'approved': false, 'reason': 'Change needs review.'}), icon: const Icon(Icons.close)),
      ]),
    ));
  }
}
