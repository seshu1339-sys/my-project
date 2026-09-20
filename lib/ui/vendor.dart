import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../data/store.dart';

class VendorPage extends StatefulWidget {
  const VendorPage({super.key, required this.store});
  final Store store;
  @override
  State<VendorPage> createState() => _VendorPageState();
}

class _VendorPageState extends State<VendorPage> {
  final name = TextEditingController(), description = TextEditingController(), address = TextEditingController();
  final docId = TextEditingController(), value = TextEditingController(), orderId = TextEditingController(), code = TextEditingController(), paymentReference = TextEditingController();
  String type = 'product';
  bool busy = false;
  Store get store => widget.store;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try { await action(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) {
    if (!store.live) return _demo();
    final uid = store.user?.uid;
    if (uid == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('Vendor studio'), actions: [IconButton(onPressed: store.logout, icon: const Icon(Icons.logout))]),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('vendorApplications').doc(uid).snapshots(),
        builder: (context, snapshot) {
          final application = snapshot.data?.data();
          if (application == null || application['status'] == 'rejected') return _applicationForm(application);
          if (application['status'] == 'payment_required') return _feePayment(application);
          if (application['status'] == 'payment_submitted') return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Your payment reference was submitted for administrator confirmation.')));
          if (application['status'] != 'approved') return Center(child: Text('Application ${application['status']}. Await administrator review.'));
          return _workspace(uid);
        },
      ),
    );
  }
  Widget _applicationForm(Map<String, dynamic>? previous) => Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
    padding: const EdgeInsets.all(24), child: Column(children: [
      Text(previous == null ? 'Apply to become a vendor' : 'Update your vendor application', style: Theme.of(context).textTheme.headlineSmall),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Shop name')),
      TextField(controller: description, decoration: const InputDecoration(labelText: 'Shop description')),
      TextField(controller: address, decoration: const InputDecoration(labelText: 'Shop address')),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : () => run(() async { await store.registerVendor(name: name.text.trim(), description: description.text, address: address.text); }), child: const Text('Submit for approval')),
      if (previous?['decisionReason'] != null) Text('Administrator reason: ${previous!['decisionReason']}'),
    ]),
  ))));
  Widget _feePayment(Map<String, dynamic> application) => Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
    padding: const EdgeInsets.all(24), child: Column(children: [
      const Text('Vendor registration reviewed', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Text('Administrator fee: ${application['feeAmount']}'),
      if ((application['decisionReason'] ?? '').toString().trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Administrator note: ${application['decisionReason']}')),
      const SizedBox(height: 8),
      const Text('Complete the vendor fee payment using the instructions provided by the administrator, then enter the payment reference below.'),
      TextField(controller: paymentReference, decoration: const InputDecoration(labelText: 'Payment reference')),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : () => run(() async { await store.submitVendorFeePayment(paymentReference.text.trim()); }), child: const Text('Submit payment reference')),
    ]),
  ))));
  Widget _workspace(String uid) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('Approved vendor workspace', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    const Text('Public changes are either published immediately by policy or held for administrator approval.'),
    const SizedBox(height: 20),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Submit a product or shop change', style: TextStyle(fontWeight: FontWeight.bold)),
      DropdownButton<String>(value: type, items: const [DropdownMenuItem(value: 'product', child: Text('Product detail')), DropdownMenuItem(value: 'price', child: Text('Price')), DropdownMenuItem(value: 'shop', child: Text('Shop detail'))], onChanged: (value) => setState(() => type = value!)),
      TextField(controller: docId, decoration: const InputDecoration(labelText: 'Product or shop ID')),
      TextField(controller: value, maxLines: 3, decoration: const InputDecoration(labelText: 'New value (for prices use a number)')),
      const SizedBox(height: 8),
      FilledButton(onPressed: busy ? null : () => run(() async {
        final field = type == 'price' ? 'price' : type == 'shop' ? 'description' : 'name';
        final newValue = type == 'price' ? double.tryParse(value.text) : value.text.trim();
        if (newValue == null || (newValue is String && newValue.isEmpty)) throw StateError('Enter a valid value.');
        final status = await store.submitVendorChange(type: type, collection: type == 'shop' ? 'shops' : 'products', docId: docId.text.trim(), changes: {field: newValue});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'approved' ? 'Published' : 'Pending administrator approval')));
      }), child: const Text('Submit change')),
    ]))),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Verified purchase', style: TextStyle(fontWeight: FontWeight.bold)),
      const Text('Enter the customer one-time code and the current shop location when the purchase is collected.'),
      TextField(controller: orderId, decoration: const InputDecoration(labelText: 'Order ID')),
      TextField(controller: code, decoration: const InputDecoration(labelText: 'Six-digit customer code')),
      FilledButton(onPressed: busy ? null : () => run(() async {
        final position = await Geolocator.getCurrentPosition();
        await store.call('redeemPurchaseCode', {'orderId': orderId.text.trim(), 'code': code.text.trim(), 'latitude': position.latitude, 'longitude': position.longitude});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verified purchase recorded')));
      }), child: const Text('Verify purchase')),
    ]))),
    // Orders carry the shops they include (shopIds), not a vendor id, and the rules
    // only let a vendor read orders containing its own shop.
    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: store.firestore.collection('vendors').doc(uid).snapshots(), builder: (_, vendor) {
      final shopId = vendor.data?.data()?['shopId'];
      if (shopId is! String) return const ListTile(leading: Icon(Icons.receipt_long), title: Text('Orders'), subtitle: Text('0 vendor orders'));
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: store.firestore.collection('orders').where('shopIds', arrayContains: shopId).limit(50).snapshots(), builder: (_, snapshot) => ListTile(leading: const Icon(Icons.receipt_long), title: const Text('Orders'), subtitle: Text('${snapshot.data?.docs.length ?? 0} vendor orders')));
    }),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: store.firestore.collection('vendorChanges').where('vendorId', isEqualTo: uid).limit(50).snapshots(), builder: (_, snapshot) => ListTile(leading: const Icon(Icons.pending_actions), title: const Text('Change history'), subtitle: Text('${snapshot.data?.docs.length ?? 0} submitted changes'))),
  ]);
  Widget _demo() => Scaffold(appBar: AppBar(title: const Text('Vendor studio')), body: const Center(child: Text('Connect Firebase to apply and manage a vendor shop.')));
  @override
  void dispose() { name.dispose(); description.dispose(); address.dispose(); docId.dispose(); value.dispose(); orderId.dispose(); code.dispose(); paymentReference.dispose(); super.dispose(); }
}
