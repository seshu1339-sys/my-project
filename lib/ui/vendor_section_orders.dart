import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'vendor_section_kit.dart';

/// Orders for the vendor's shop. Orders carry the shops they include (shopIds), not a vendor id, and the rules only let a vendor read orders
/// containing its own shop.
class VendorOrdersSection extends StatefulWidget {
  const VendorOrdersSection({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;
  @override
  State<VendorOrdersSection> createState() => _VendorOrdersSectionState();
}

class _VendorOrdersSectionState extends State<VendorOrdersSection> with VendorSectionState {
  Store get store => widget.store;

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendors').doc(widget.uid).snapshots(),
    builder: (_, vendor) {
      final shopId = vendor.data?.data()?['shopId'];
      if (shopId is! String) return const ListTile(leading: Icon(Icons.receipt_long), title: Text('Orders'), subtitle: Text('0 vendor orders'));
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('orders').where('shopIds', arrayContains: shopId).limit(50).snapshots(),
        builder: (_, snapshot) {
          final docs = snapshot.data?.docs ?? const [];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(leading: const Icon(Icons.receipt_long), title: const Text('Orders'), subtitle: Text('${docs.length} vendor orders')),
            for (final doc in docs) _orderTile(doc),
          ]);
        },
      );
    },
  );

  Widget _orderTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final order = doc.data();
    final status = '${order['status']}';
    final lines = [for (final l in (order['lines'] as List? ?? const [])) '${(l as Map)['name']} × ${l['quantity']}'].join(', ');
    Widget action(String label, String next) => OutlinedButton(
      onPressed: busy
          ? null
          : () => run(() async {
              await store.updateVendorOrder(doc.id, next);
              toast('Order marked $next');
            }),
      child: Text(label),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Order ${doc.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('$lines • Total ${order['total']}'),
          Text('${order['address']}'),
          Text('Payment: ${order['paymentMethod']} • ${order['paymentStatus']}'),
          Text('Status: $status'),
          Wrap(spacing: 8, children: [
            if (status == 'submitted') action('Confirm order', 'confirmed'),
            if (status == 'confirmed') action('Mark fulfilled', 'fulfilled'),
            if (status == 'submitted' || status == 'confirmed') action('Cancel order', 'cancelled'),
          ]),
        ]),
      ),
    );
  }
}
