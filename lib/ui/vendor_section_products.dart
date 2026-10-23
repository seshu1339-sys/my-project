import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'vendor_section_kit.dart';

/// "Add a product or material": its own form, its own photo, its own busy flag.
class VendorAddProductSection extends StatefulWidget {
  const VendorAddProductSection({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;
  @override
  State<VendorAddProductSection> createState() => _VendorAddProductSectionState();
}

class _VendorAddProductSectionState extends State<VendorAddProductSection> with VendorSectionState {
  final name = TextEditingController(), price = TextEditingController(), stock = TextEditingController(), unit = TextEditingController(), description = TextEditingController();
  String? categoryId, imageUrl;
  Uint8List? imageBytes;
  Store get store => widget.store;
  String get uid => widget.uid;

  @override
  void dispose() {
    for (final c in [name, price, stock, unit, description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _add() async {
    final p = double.tryParse(price.text.trim());
    final s = int.tryParse(stock.text.trim());
    if (name.text.trim().length < 2) throw StateError('Enter the product or material name.');
    if (p == null || p < 0) throw StateError('Enter a valid price.');
    if (s == null || s < 0) throw StateError('Enter the stock quantity as a whole number.');
    final status = await store.submitVendorChange(type: 'newProduct', collection: 'products', docId: '', changes: {
      'name': name.text.trim(), 'price': p, 'stock': s,
      if (unit.text.trim().isNotEmpty) 'unit': unit.text.trim(),
      if (description.text.trim().isNotEmpty) 'description': description.text.trim(),
      if (categoryId != null) 'categoryId': categoryId,
      if (imageUrl != null) 'imageUrl': imageUrl,
    });
    for (final c in [name, price, stock, unit, description]) {
      c.clear();
    }
    setState(() {
      imageUrl = null;
      imageBytes = null;
      categoryId = null;
    });
    toast(vendorPublished(status));
  }

  @override
  Widget build(BuildContext context) => vendorCard('Add a product or material', [
    TextField(controller: name, decoration: const InputDecoration(labelText: 'Product or material name')),
    TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
    TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock quantity')),
    TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit (for example kg, bag, each)')),
    TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Product description')),
    DropdownButtonFormField<String>(
      initialValue: categoryId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Category'),
      items: [for (final c in store.entries('categories')) DropdownMenuItem(value: c.id, child: Text(c.text('name')))],
      onChanged: (v) => setState(() => categoryId = v),
    ),
    const SizedBox(height: 8),
    if (imageBytes != null)
      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(imageBytes!, height: 120, fit: BoxFit.cover))
    else if (imageUrl != null)
      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(imageUrl!, height: 120, fit: BoxFit.cover)),
    Wrap(spacing: 8, children: [
      if (vendorLibraryEnforced(store))
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final chosen = await pickLibraryImage(context, store);
                  if (chosen != null && mounted) {
                    setState(() {
                      imageUrl = chosen.text('imageUrl');
                      imageBytes = null;
                    });
                  }
                },
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from image library'),
        )
      else
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => run(() async {
                  final file = await vendorPickImage();
                  if (file == null) return;
                  final bytes = await file.readAsBytes();
                  final url = await store.upload(file, folder: 'vendorProducts/$uid');
                  if (mounted) {
                    setState(() {
                      imageUrl = url;
                      imageBytes = bytes;
                    });
                  }
                }),
          icon: const Icon(Icons.upload),
          label: const Text('Upload product photo'),
        ),
      FilledButton(onPressed: busy ? null : () => run(_add), child: const Text('Submit product')),
    ]),
  ]);
}

/// "My products and materials": the vendor's own shop's products (including ones the office added for the shop), with hide / price / stock /
/// photo actions. Independent of the form above.
class VendorMyProductsSection extends StatefulWidget {
  const VendorMyProductsSection({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;
  @override
  State<VendorMyProductsSection> createState() => _VendorMyProductsSectionState();
}

class _VendorMyProductsSectionState extends State<VendorMyProductsSection> with VendorSectionState {
  Store get store => widget.store;
  String get uid => widget.uid;

  Future<void> _changePhoto(String productId) async {
    if (vendorLibraryEnforced(store)) {
      final chosen = await pickLibraryImage(context, store);
      if (chosen == null) return;
      await run(() async {
        toast(vendorPublished(await store.submitVendorChange(type: 'product', collection: 'products', docId: productId, changes: {'imageUrl': chosen.text('imageUrl')})));
      });
    } else {
      await run(() async {
        final file = await vendorPickImage();
        if (file == null) return;
        final url = await store.upload(file, folder: 'vendorProducts/$uid');
        toast(vendorPublished(await store.submitVendorChange(type: 'product', collection: 'products', docId: productId, changes: {'imageUrl': url})));
      });
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendors').doc(uid).snapshots(),
    builder: (context, vendorSnapshot) {
      final shopId = vendorSnapshot.data?.data()?['shopId'];
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: (shopId is String && shopId.isNotEmpty
                ? store.firestore.collection('products').where('shopId', isEqualTo: shopId)
                : store.firestore.collection('products').where('ownerId', isEqualTo: uid))
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? const [];
          return vendorCard('My products and materials', [
            if (docs.isEmpty) const Text('No published products yet. Submitted products appear here once published.'),
            for (final doc in docs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: (doc.data()['imageUrl'] ?? '').toString().isEmpty
                    ? const Icon(Icons.inventory_2_outlined)
                    : SizedBox(width: 44, height: 44, child: Image.network('${doc.data()['imageUrl']}', fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined))),
                title: Text('${doc.data()['name']}'),
                subtitle: Text('Price ${doc.data()['price']} • Stock ${doc.data()['stock'] ?? 0}${doc.data()['active'] == false ? ' • Hidden from customers' : ''}'),
                trailing: Wrap(children: [
                  IconButton(
                    tooltip: doc.data()['active'] == false ? 'Show on site' : 'Hide from site',
                    icon: Icon(doc.data()['active'] == false ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            toast(vendorPublished(await store.submitVendorChange(type: 'visibility', collection: 'products', docId: doc.id, changes: {'active': doc.data()['active'] == false})));
                          }),
                  ),
                  IconButton(
                    tooltip: 'Update price',
                    icon: const Icon(Icons.sell_outlined),
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final n = await askVendorNumber(context, 'Update price', 'New price', integer: false, initial: '${doc.data()['price'] ?? ''}');
                            if (n == null) return;
                            toast(vendorPublished(await store.submitVendorChange(type: 'price', collection: 'products', docId: doc.id, changes: {'price': n.toDouble()})));
                          }),
                  ),
                  IconButton(
                    tooltip: 'Update stock',
                    icon: const Icon(Icons.inventory_outlined),
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final n = await askVendorNumber(context, 'Update stock', 'Stock quantity', integer: true, initial: '${doc.data()['stock'] ?? 0}');
                            if (n == null) return;
                            toast(vendorPublished(await store.submitVendorChange(type: 'stock', collection: 'products', docId: doc.id, changes: {'stock': n.toInt()})));
                          }),
                  ),
                  IconButton(tooltip: 'Change photo', icon: const Icon(Icons.add_photo_alternate_outlined), onPressed: busy ? null : () => _changePhoto(doc.id)),
                ]),
              ),
          ]);
        },
      );
    },
  );
}
