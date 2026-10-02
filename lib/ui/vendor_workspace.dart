import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/location.dart';

/// Business features. Only built once the application status is approved; the
/// server independently refuses every one of these actions for anyone else.
class VendorWorkspace extends StatefulWidget {
  const VendorWorkspace({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;
  @override
  State<VendorWorkspace> createState() => _VendorWorkspaceState();
}

class _VendorWorkspaceState extends State<VendorWorkspace> {
  final docId = TextEditingController(), value = TextEditingController(), orderId = TextEditingController(), code = TextEditingController();
  final pName = TextEditingController(), pPrice = TextEditingController(), pStock = TextEditingController(), pUnit = TextEditingController(), pDescription = TextEditingController();
  final xName = TextEditingController(), xPrice = TextEditingController(), xDuration = TextEditingController();
  String type = 'product';
  String? categoryId, productImageUrl, exclusiveImageUrl;
  Uint8List? productImageBytes, exclusiveImageBytes;
  bool busy = false;
  Store get store => widget.store;
  String get uid => widget.uid;
  void toast(Object message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message'))); }
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try { await action(); } catch (e) { toast(e); }
    if (mounted) setState(() => busy = false);
  }
  String published(String status) => status == 'approved' ? 'Published' : 'Pending administrator approval';

  Future<XFile?> pickImage() => ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);

  // Off by default: existing free-upload behaviour is preserved until the admin has populated
  // the Product Image Library and explicitly turns this on.
  bool get libraryEnforced => store.business.text('productImageLibraryEnforced', 'false').trim().toLowerCase() == 'true';

  /// Lets the vendor pick an already-approved image instead of uploading its own; the same
  /// image URL is reused across every product that picks it (no duplicate file per vendor).
  Future<Entry?> pickLibraryImage() {
    final images = store.entries('productImageLibrary').where((e) => e.active).toList();
    return showDialog<Entry>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Choose a product image'),
      content: SizedBox(width: 420, child: images.isEmpty
          ? const Text('No approved images are available yet. Ask the administrator to add some to the Product Image Library.')
          : SingleChildScrollView(child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final img in images) Semantics(button: true, label: 'Choose ${img.text('name', img.id)}', child: InkWell(
                onTap: () => Navigator.pop(dialog, img),
                child: SizedBox(width: 110, child: Column(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(img.text('imageUrl'), width: 100, height: 100, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined))),
                  Text(img.text('name', img.id), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ])),
              )),
            ])),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel'))],
    ));
  }

  Future<void> addProduct() async {
    final price = double.tryParse(pPrice.text.trim());
    final stock = int.tryParse(pStock.text.trim());
    if (pName.text.trim().length < 2) throw StateError('Enter the product or material name.');
    if (price == null || price < 0) throw StateError('Enter a valid price.');
    if (stock == null || stock < 0) throw StateError('Enter the stock quantity as a whole number.');
    final status = await store.submitVendorChange(type: 'newProduct', collection: 'products', docId: '', changes: {
      'name': pName.text.trim(), 'price': price, 'stock': stock,
      if (pUnit.text.trim().isNotEmpty) 'unit': pUnit.text.trim(),
      if (pDescription.text.trim().isNotEmpty) 'description': pDescription.text.trim(),
      if (categoryId != null) 'categoryId': categoryId,
      if (productImageUrl != null) 'imageUrl': productImageUrl,
    });
    for (final c in [pName, pPrice, pStock, pUnit, pDescription]) { c.clear(); }
    setState(() { productImageUrl = null; productImageBytes = null; categoryId = null; });
    toast(published(status));
  }

  Future<void> changeProductPhoto(String productId) async {
    if (libraryEnforced) {
      final chosen = await pickLibraryImage();
      if (chosen == null) return;
      await run(() async {
        toast(published(await store.submitVendorChange(type: 'product', collection: 'products', docId: productId, changes: {'imageUrl': chosen.text('imageUrl')})));
      });
    } else {
      await run(() async {
        final file = await pickImage();
        if (file == null) return;
        final url = await store.upload(file, folder: 'vendorProducts/$uid');
        toast(published(await store.submitVendorChange(type: 'product', collection: 'products', docId: productId, changes: {'imageUrl': url})));
      });
    }
  }

  Future<num?> askNumber(String title, String label, {required bool integer, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final ok = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label)),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Save'))],
    ));
    final text = controller.text.trim();
    controller.dispose();
    if (ok != true) return null;
    final parsed = integer ? int.tryParse(text) : double.tryParse(text);
    if (parsed == null || parsed < 0) throw StateError(integer ? 'Enter a whole number.' : 'Enter a valid number.');
    return parsed;
  }

  Widget _card(String title, List<Widget> children, {String? note}) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    if (note != null) Text(note),
    ...children,
  ])));

  Widget _shopPhotosSection() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendorShopPhotos').where('vendorId', isEqualTo: uid).snapshots(),
    builder: (context, snapshot) {
      final bySlot = <int, Map<String, dynamic>>{
        for (final doc in snapshot.data?.docs ?? const []) (doc.data()['slot'] as num).toInt(): doc.data(),
      };
      // Admin-configurable (settings/business.vendorPhotoLimit), default 2 —
      // the limit this app has always had.
      final limit = store.business.number('vendorPhotoLimit', 2).round().clamp(1, 9);
      return _card('Shop photos', [
        Wrap(spacing: 16, runSpacing: 12, children: [for (var slot = 1; slot <= limit; slot++) _shopPhotoSlot(slot, bySlot[slot])]),
      ], note: 'Up to $limit photo${limit == 1 ? '' : 's'} of your shop. Each stays pending until the administrator approves it, and is hidden from customers until then.');
    },
  );

  Widget _shopPhotoSlot(int slot, Map<String, dynamic>? data) {
    final status = data?['status'] as String?;
    final path = data?['path'] as String?;
    final reason = (data?['decisionReason'] ?? '').toString();
    return SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(8), child: path == null
          ? Container(width: 160, height: 120, color: Colors.black12, child: const Icon(Icons.storefront_outlined))
          : FutureBuilder<String>(
              future: FirebaseStorage.instance.ref(path).getDownloadURL(),
              builder: (context, snap) => snap.hasData
                  ? Image.network(snap.data!, width: 160, height: 120, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined))
                  : Container(width: 160, height: 120, color: Colors.black12),
            )),
      const SizedBox(height: 4),
      Text(switch (status) {
        'pending' => 'Pending admin review',
        'approved' => 'Approved',
        'rejected' => 'Rejected${reason.isEmpty ? '' : ': $reason'}',
        _ => 'Empty slot',
      }),
      OutlinedButton(onPressed: busy ? null : () => run(() async {
        final file = await pickImage();
        if (file == null) return;
        await store.uploadShopPhoto(slot, file);
        await store.call('submitShopPhoto', {'slot': slot});
        toast('Photo submitted for admin review');
      }), child: Text(path == null ? 'Upload' : 'Replace')),
    ]));
  }

  Widget _exclusivesSection(Map<String, dynamic>? vendorData) {
    if (vendorData?['specialCategoryExclusives'] != true) return const SizedBox.shrink();
    final maxDays = (vendorData?['exclusivesMaxDurationDays'] as num?)?.toInt() ?? 0;
    return _card('Special Category Exclusives', [
      TextField(controller: xName, decoration: const InputDecoration(labelText: 'Item or design name')),
      TextField(controller: xPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
      TextField(controller: xDuration, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Active duration in days (up to $maxDays)')),
      const SizedBox(height: 8),
      if (exclusiveImageBytes != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(exclusiveImageBytes!, height: 120, fit: BoxFit.cover)),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: busy ? null : () => run(() async {
          final file = await pickImage();
          if (file == null) return;
          final bytes = await file.readAsBytes();
          final url = await store.upload(file, folder: 'vendorProducts/$uid');
          if (mounted) setState(() { exclusiveImageUrl = url; exclusiveImageBytes = bytes; });
        }), icon: const Icon(Icons.upload), label: const Text('Upload photo')),
        FilledButton(onPressed: busy ? null : () => run(() async {
          final price = double.tryParse(xPrice.text.trim());
          final days = int.tryParse(xDuration.text.trim());
          if (xName.text.trim().length < 2) throw StateError('Enter a name for the item.');
          if (price == null || price < 0) throw StateError('Enter a valid price.');
          if (days == null || days < 1) throw StateError('Enter the active duration in days.');
          if (exclusiveImageUrl == null) throw StateError('Upload a photo first.');
          await store.call('submitExclusiveItem', {'name': xName.text.trim(), 'price': price, 'imageUrl': exclusiveImageUrl, 'durationDays': days});
          for (final c in [xName, xPrice, xDuration]) { c.clear(); }
          setState(() { exclusiveImageUrl = null; exclusiveImageBytes = null; });
          toast('Exclusive item published');
        }), child: const Text('Publish exclusive item')),
      ]),
      const SizedBox(height: 12),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('products').where('ownerId', isEqualTo: uid).where('isExclusive', isEqualTo: true).where('active', isEqualTo: true).snapshots(),
        builder: (context, snapshot) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Active exclusives', style: Theme.of(context).textTheme.titleSmall),
          for (final doc in snapshot.data?.docs ?? const []) ListTile(
            contentPadding: EdgeInsets.zero, dense: true,
            title: Text('${doc.data()['name']}'), subtitle: Text('₹${doc.data()['price']} • expires ${(doc.data()['expiresAt'] ?? '').toString().substring(0, 10)}'),
          ),
          if ((snapshot.data?.docs ?? const []).isEmpty) const Text('No active exclusive items yet.'),
        ]),
      ),
      const SizedBox(height: 8),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('products').where('ownerId', isEqualTo: uid).where('isExclusive', isEqualTo: true).where('active', isEqualTo: false).snapshots(),
        builder: (context, snapshot) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Archived (reactivate within 15 days)', style: Theme.of(context).textTheme.titleSmall),
          for (final doc in snapshot.data?.docs ?? const []) ListTile(
            contentPadding: EdgeInsets.zero, dense: true,
            title: Text('${doc.data()['name']}'), subtitle: Text('₹${doc.data()['price']}'),
            trailing: OutlinedButton(onPressed: busy ? null : () => run(() async {
              final days = await askNumber('Reactivate item', 'Active duration in days (up to $maxDays)', integer: true);
              if (days == null) return;
              await store.call('reactivateExclusiveItem', {'productId': doc.id, 'durationDays': days.toInt()});
              toast('Item reactivated');
            }), child: const Text('Reactivate')),
          ),
          if ((snapshot.data?.docs ?? const []).isEmpty) const Text('Nothing archived right now.'),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('Approved vendor workspace', style: Theme.of(context).textTheme.headlineSmall),
    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('vendors').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final code = snapshot.data?.data()?['vendorCode'] as String?;
        if (code == null) return const SizedBox.shrink();
        return Padding(padding: const EdgeInsets.only(top: 4), child: Text('Vendor ID: $code', style: Theme.of(context).textTheme.bodyMedium));
      },
    ),
    const SizedBox(height: 8),
    const Text('Your application is approved. Public changes are either published immediately by policy or held for administrator approval.'),
    const SizedBox(height: 20),
    _shopPhotosSection(),
    const SizedBox(height: 20),
    _card('Add a product or material', [
      TextField(controller: pName, decoration: const InputDecoration(labelText: 'Product or material name')),
      TextField(controller: pPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
      TextField(controller: pStock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock quantity')),
      TextField(controller: pUnit, decoration: const InputDecoration(labelText: 'Unit (for example kg, bag, each)')),
      TextField(controller: pDescription, maxLines: 2, decoration: const InputDecoration(labelText: 'Product description')),
      DropdownButtonFormField<String>(
        initialValue: categoryId, isExpanded: true, decoration: const InputDecoration(labelText: 'Category'),
        items: [for (final c in store.entries('categories')) DropdownMenuItem(value: c.id, child: Text(c.text('name')))],
        onChanged: (v) => setState(() => categoryId = v),
      ),
      const SizedBox(height: 8),
      if (productImageBytes != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(productImageBytes!, height: 120, fit: BoxFit.cover))
      else if (productImageUrl != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(productImageUrl!, height: 120, fit: BoxFit.cover)),
      Wrap(spacing: 8, children: [
        if (libraryEnforced)
          OutlinedButton.icon(onPressed: busy ? null : () async {
            final chosen = await pickLibraryImage();
            if (chosen != null && mounted) setState(() { productImageUrl = chosen.text('imageUrl'); productImageBytes = null; });
          }, icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose from image library'))
        else
          OutlinedButton.icon(onPressed: busy ? null : () => run(() async {
            final file = await pickImage();
            if (file == null) return;
            final bytes = await file.readAsBytes();
            final url = await store.upload(file, folder: 'vendorProducts/$uid');
            if (mounted) setState(() { productImageUrl = url; productImageBytes = bytes; });
          }), icon: const Icon(Icons.upload), label: const Text('Upload product photo')),
        FilledButton(onPressed: busy ? null : () => run(addProduct), child: const Text('Submit product')),
      ]),
    ]),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('products').where('ownerId', isEqualTo: uid).limit(100).snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        return _card('My products and materials', [
          if (docs.isEmpty) const Text('No published products yet. Submitted products appear here once published.'),
          for (final doc in docs) ListTile(
            contentPadding: EdgeInsets.zero,
            leading: (doc.data()['imageUrl'] ?? '').toString().isEmpty ? const Icon(Icons.inventory_2_outlined) : SizedBox(width: 44, height: 44, child: Image.network('${doc.data()['imageUrl']}', fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined))),
            title: Text('${doc.data()['name']}'),
            subtitle: Text('Price ${doc.data()['price']} • Stock ${doc.data()['stock'] ?? 0}'),
            trailing: Wrap(children: [
              IconButton(tooltip: 'Update price', icon: const Icon(Icons.sell_outlined), onPressed: busy ? null : () => run(() async {
                final n = await askNumber('Update price', 'New price', integer: false, initial: '${doc.data()['price'] ?? ''}');
                if (n == null) return;
                toast(published(await store.submitVendorChange(type: 'price', collection: 'products', docId: doc.id, changes: {'price': n.toDouble()})));
              })),
              IconButton(tooltip: 'Update stock', icon: const Icon(Icons.inventory_outlined), onPressed: busy ? null : () => run(() async {
                final n = await askNumber('Update stock', 'Stock quantity', integer: true, initial: '${doc.data()['stock'] ?? 0}');
                if (n == null) return;
                toast(published(await store.submitVendorChange(type: 'stock', collection: 'products', docId: doc.id, changes: {'stock': n.toInt()})));
              })),
              IconButton(tooltip: 'Change photo', icon: const Icon(Icons.add_photo_alternate_outlined), onPressed: busy ? null : () => changeProductPhoto(doc.id)),
            ]),
          ),
        ]);
      },
    ),
    _card('Submit a product or shop change', [
      DropdownButton<String>(value: type, isExpanded: true, items: const [DropdownMenuItem(value: 'product', child: Text('Product detail')), DropdownMenuItem(value: 'price', child: Text('Price')), DropdownMenuItem(value: 'shop', child: Text('Shop detail'))], onChanged: (value) => setState(() => type = value!)),
      TextField(controller: docId, decoration: const InputDecoration(labelText: 'Product or shop ID')),
      TextField(controller: value, maxLines: 3, decoration: const InputDecoration(labelText: 'New value (for prices use a number)')),
      const SizedBox(height: 8),
      FilledButton(onPressed: busy ? null : () => run(() async {
        final field = type == 'price' ? 'price' : type == 'shop' ? 'description' : 'name';
        final newValue = type == 'price' ? double.tryParse(value.text) : value.text.trim();
        if (newValue == null || (newValue is String && newValue.isEmpty)) throw StateError('Enter a valid value.');
        final status = await store.submitVendorChange(type: type, collection: type == 'shop' ? 'shops' : 'products', docId: docId.text.trim(), changes: {field: newValue});
        toast(published(status));
      }), child: const Text('Submit change')),
    ]),
    _card('Verified purchase', [
      TextField(controller: orderId, decoration: const InputDecoration(labelText: 'Order ID')),
      TextField(controller: code, decoration: const InputDecoration(labelText: 'Six-digit customer code')),
      FilledButton(onPressed: busy ? null : () => run(() async {
        final position = await currentPosition();
        await store.call('redeemPurchaseCode', {'orderId': orderId.text.trim(), 'code': code.text.trim(), 'latitude': position.latitude, 'longitude': position.longitude});
        toast('Verified purchase recorded');
      }), child: const Text('Verify purchase')),
    ], note: 'Enter the customer one-time code and the current shop location when the purchase is collected.'),
    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: store.firestore.collection('vendors').doc(uid).snapshots(), builder: (_, vendor) => _exclusivesSection(vendor.data?.data())),
    // Orders carry the shops they include (shopIds), not a vendor id, and the rules
    // only let a vendor read orders containing its own shop.
    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: store.firestore.collection('vendors').doc(uid).snapshots(), builder: (_, vendor) {
      final shopId = vendor.data?.data()?['shopId'];
      if (shopId is! String) return const ListTile(leading: Icon(Icons.receipt_long), title: Text('Orders'), subtitle: Text('0 vendor orders'));
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: store.firestore.collection('orders').where('shopIds', arrayContains: shopId).limit(50).snapshots(), builder: (_, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(leading: const Icon(Icons.receipt_long), title: const Text('Orders'), subtitle: Text('${docs.length} vendor orders')),
          for (final doc in docs) _orderTile(doc),
        ]);
      });
    }),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: store.firestore.collection('vendorChanges').where('vendorId', isEqualTo: uid).limit(50).snapshots(), builder: (_, snapshot) {
      final docs = snapshot.data?.docs ?? const [];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(leading: const Icon(Icons.pending_actions), title: const Text('Change history'), subtitle: Text('${docs.length} submitted changes')),
        for (final doc in docs) ListTile(dense: true, title: Text('${doc.data()['type']} • ${doc.data()['newValue']?['name'] ?? doc.data()['docId']}'), subtitle: Text('${doc.data()['status']}${doc.data()['decisionReason'] != null && '${doc.data()['decisionReason']}'.isNotEmpty ? ' — ${doc.data()['decisionReason']}' : ''}')),
      ]);
    }),
  ]);

  Widget _orderTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final order = doc.data();
    final status = '${order['status']}';
    final lines = [for (final l in (order['lines'] as List? ?? const [])) '${(l as Map)['name']} × ${l['quantity']}'].join(', ');
    Widget action(String label, String next) => OutlinedButton(onPressed: busy ? null : () => run(() async { await store.updateVendorOrder(doc.id, next); toast('Order marked $next'); }), child: Text(label));
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    ])));
  }

  @override
  void dispose() {
    for (final c in [docId, value, orderId, code, pName, pPrice, pStock, pUnit, pDescription, xName, xPrice, xDuration]) { c.dispose(); }
    super.dispose();
  }
}
