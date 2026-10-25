import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/vendor_items.dart';
import 'text_prompt_dialog.dart';

/// "My vendors and services" in the staff app: everything this staff member added (Staff > Add), with its state (waiting for the admin,
/// live, or not approved and why) and its ID (Vendor ID, or Provider ID for a service provider). A live vendor's items show their price; a price lasts 24 hours, so the staff member who
/// added the vendor enters a new one when it runs out (functions/staff-additions.js renewStaffVendorPrice).
class FieldMyAdditions extends StatelessWidget {
  const FieldMyAdditions({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  List<Entry> _rows(QuerySnapshot<Map<String, dynamic>>? s) => [for (final d in s?.docs ?? const []) Entry(d.id, d.data())];

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('staffAdditions').where('staffUid', isEqualTo: uid).limit(200).snapshots(),
    builder: (context, additions) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('products').where('addedByStaffUid', isEqualTo: uid).limit(400).snapshots(),
      builder: (context, products) => StaffAdditionsView(
        additions: _rows(additions.data),
        products: _rows(products.data),
        now: DateTime.now(),
        failed: additions.hasError,
        onNewPrice: (productId, price) => store.call('renewStaffVendorPrice', {'productId': productId, 'price': price}),
      ),
    ),
  );
}

/// The list itself, newest first.
class StaffAdditionsView extends StatelessWidget {
  const StaffAdditionsView({super.key, required this.additions, required this.products, required this.now, required this.onNewPrice, this.failed = false});
  final List<Entry> additions, products;
  final DateTime now;
  final bool failed;
  final Future<void> Function(String productId, double price) onNewPrice;

  static String stateOf(Entry addition) => switch (addition.text('status')) {
    'approved' => 'Live',
    'rejected' => 'Not approved${addition.text('decisionReason').isEmpty ? '' : ': ${addition.text('decisionReason')}'}',
    _ => 'Waiting for the administrator',
  };

  Future<void> _newPrice(BuildContext context, Entry item) async {
    final text = await askText(
      context,
      title: 'Today\'s price: ${item.text('name')}',
      label: 'Price for ${item.text('unit')} (₹)',
      helper: 'It stays for $vendorPriceValidHours hours.',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      fieldKey: ValueKey('staff-new-price-${item.id}'),
    );
    final price = double.tryParse(text ?? '');
    if (price == null || price <= 0 || !context.mounted) return;
    try {
      await onNewPrice(item.id, price);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: ₹$price for ${item.text('unit')}. Customers see it now.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...additions]..sort((a, b) => '${b.data['submittedAt'] ?? ''}'.compareTo('${a.data['submittedAt'] ?? ''}'));
    final expiredCount = [for (final p in products) if (vendorPriceExpired(p.data, now)) p].length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My vendors and services', style: Theme.of(context).textTheme.titleLarge),
        Text('${additions.length} added by you${expiredCount == 0 ? '' : ' • $expiredCount price${expiredCount == 1 ? '' : 's'} to renew'}', key: const ValueKey('staff-additions-count')),
        if (failed) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Your vendors could not load.')),
        if (!failed && additions.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nobody added yet. Tap Add above.')),
        for (final a in sorted) _card(context, a),
      ],
    );
  }

  Widget _card(BuildContext context, Entry a) {
    final provider = a.text('kind') == 'provider';
    final person = Map<String, dynamic>.from((provider ? a.data['provider'] : a.data['vendor']) as Map? ?? const {});
    final code = provider ? a.text('providerCode') : a.text('vendorCode');
    final live = a.text('status') == 'approved';
    final items = [for (final p in products) if (p.text('ownerId') == a.id) p];
    return Card(
      key: ValueKey('staff-addition-${a.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(live ? (provider ? Icons.home_repair_service : Icons.storefront) : a.text('status') == 'rejected' ? Icons.cancel_outlined : Icons.hourglass_top),
            const SizedBox(width: 8),
            Expanded(child: Text('${person['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold))),
          ]),
          if (provider) Text('${a.text('serviceName')} • ₹${a.data['hourlyRate'] ?? ''} per hour'),
          Text([if (code.isNotEmpty) '${provider ? 'Provider' : 'Vendor'} ID: $code', if ('${person['phone'] ?? ''}'.isNotEmpty) 'Phone: ${person['phone']}'].join(' • ')),
          Text(stateOf(a), key: ValueKey('staff-addition-state-${a.id}')),
          if (live)
            for (final item in items)
              ListTile(
                key: ValueKey('staff-item-${item.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item.text('name')),
                subtitle: Text(vendorPriceLine(item.data, now), style: vendorPriceExpired(item.data, now) ? TextStyle(color: Theme.of(context).colorScheme.error) : null),
                trailing: OutlinedButton(
                  key: ValueKey('staff-renew-${item.id}'),
                  onPressed: () => _newPrice(context, item),
                  child: const Text('New price'),
                ),
              ),
        ]),
      ),
    );
  }
}
