import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/location.dart';
import 'vendor_section_kit.dart';

/// "Submit a product or shop change": a free-form change request. Its own boxes and busy flag.
class VendorChangeRequestSection extends StatefulWidget {
  const VendorChangeRequestSection({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;
  @override
  State<VendorChangeRequestSection> createState() => _VendorChangeRequestSectionState();
}

class _VendorChangeRequestSectionState extends State<VendorChangeRequestSection> with VendorSectionState {
  final docId = TextEditingController(), value = TextEditingController();
  String type = 'product';
  Store get store => widget.store;

  @override
  void dispose() {
    docId.dispose();
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => vendorCard('Submit a product or shop change', [
    DropdownButton<String>(
      value: type,
      isExpanded: true,
      items: const [DropdownMenuItem(value: 'product', child: Text('Product detail')), DropdownMenuItem(value: 'price', child: Text('Price')), DropdownMenuItem(value: 'shop', child: Text('Shop detail'))],
      onChanged: (v) => setState(() => type = v!),
    ),
    TextField(controller: docId, decoration: const InputDecoration(labelText: 'Product or shop ID')),
    TextField(controller: value, maxLines: 3, decoration: const InputDecoration(labelText: 'New value (for prices use a number)')),
    const SizedBox(height: 8),
    FilledButton(
      onPressed: busy
          ? null
          : () => run(() async {
              final field = type == 'price' ? 'price' : type == 'shop' ? 'description' : 'name';
              final newValue = type == 'price' ? double.tryParse(value.text) : value.text.trim();
              if (newValue == null || (newValue is String && newValue.isEmpty)) throw StateError('Enter a valid value.');
              final status = await store.submitVendorChange(type: type, collection: type == 'shop' ? 'shops' : 'products', docId: docId.text.trim(), changes: {field: newValue});
              toast(vendorPublished(status));
            }),
      child: const Text('Submit change'),
    ),
  ]);
}

/// "Verified purchase": the customer's one-time code, with the shop's current location.
class VendorVerifyPurchaseSection extends StatefulWidget {
  const VendorVerifyPurchaseSection({super.key, required this.store});
  final Store store;
  @override
  State<VendorVerifyPurchaseSection> createState() => _VendorVerifyPurchaseSectionState();
}

class _VendorVerifyPurchaseSectionState extends State<VendorVerifyPurchaseSection> with VendorSectionState {
  final orderId = TextEditingController(), code = TextEditingController();

  @override
  void dispose() {
    orderId.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => vendorCard('Verified purchase', [
    TextField(controller: orderId, decoration: const InputDecoration(labelText: 'Order ID')),
    TextField(controller: code, decoration: const InputDecoration(labelText: 'Six-digit customer code')),
    FilledButton(
      onPressed: busy
          ? null
          : () => run(() async {
              final position = await currentPosition();
              await widget.store.call('redeemPurchaseCode', {'orderId': orderId.text.trim(), 'code': code.text.trim(), 'latitude': position.latitude, 'longitude': position.longitude});
              toast('Verified purchase recorded');
            }),
      child: const Text('Verify purchase'),
    ),
  ], note: 'Enter the customer one-time code and the current shop location when the purchase is collected.');
}

/// What the vendor sent for approval and what the administrator decided.
class VendorChangeHistorySection extends StatelessWidget {
  const VendorChangeHistorySection({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendorChanges').where('vendorId', isEqualTo: uid).limit(50).snapshots(),
    builder: (_, snapshot) {
      final docs = snapshot.data?.docs ?? const [];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(leading: const Icon(Icons.pending_actions), title: const Text('Change history'), subtitle: Text('${docs.length} submitted changes')),
        for (final doc in docs)
          ListTile(
            dense: true,
            title: Text('${doc.data()['type']} • ${doc.data()['newValue']?['name'] ?? doc.data()['docId']}'),
            subtitle: Text('${doc.data()['status']}${doc.data()['decisionReason'] != null && '${doc.data()['decisionReason']}'.isNotEmpty ? ' — ${doc.data()['decisionReason']}' : ''}'),
          ),
      ]);
    },
  );
}
