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
  bool isService = false;
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
    final status = await store.submitVendorChange(type: 'newProduct', collection: isService ? 'services' : 'products', docId: '', changes: {
      'name': name.text.trim(), 'price': p, 'stock': s,
      if (isService) 'kind': 'service',
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

  // Photo 1 (the shop itself) is required before items can be added; it may still be waiting for the admin.
  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendorShopPhotos').doc('${uid}_1').snapshots(),
    builder: (context, photo) => _form(context, shopPhotoReady: const ['pending', 'approved'].contains(photo.data?.data()?['status'])),
  );

  Widget _form(BuildContext context, {required bool shopPhotoReady}) => vendorCard('Add a product or material', [
    if (!shopPhotoReady)
      Text('Add photo 1, a photo of your shop (Shop photos above), first: it is required before you add items.', key: const ValueKey('shop-photo-required'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
    TextField(controller: name, decoration: const InputDecoration(labelText: 'Product or material name')),
    TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
    TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock quantity')),
    TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit (for example kg, bag, each)')),
    TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Product description')),
    SwitchListTile(
      key: const ValueKey('vendor-is-service'),
      contentPadding: EdgeInsets.zero,
      value: isService,
      onChanged: (v) => setState(() => isService = v),
      title: const Text('This is a service (not a product)'),
    ),
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
      FilledButton(onPressed: busy || !shopPhotoReady ? null : () => run(_add), child: const Text('Submit product')),
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

  Future<void> _changePhoto(String collection, String productId) async {
    if (vendorLibraryEnforced(store)) {
      final chosen = await pickLibraryImage(context, store);
      if (chosen == null) return;
      await run(() async {
        toast(vendorPublished(await store.submitVendorChange(type: 'product', collection: collection, docId: productId, changes: {'imageUrl': chosen.text('imageUrl')})));
      });
    } else {
      await run(() async {
        final file = await vendorPickImage();
        if (file == null) return;
        final url = await store.upload(file, folder: 'vendorProducts/$uid');
        toast(vendorPublished(await store.submitVendorChange(type: 'product', collection: collection, docId: productId, changes: {'imageUrl': url})));
      });
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendors').doc(uid).snapshots(),
    builder: (context, vendorSnapshot) {
      final shopId = vendorSnapshot.data?.data()?['shopId'];
      Query<Map<String, dynamic>> mine(String collection) => (shopId is String && shopId.isNotEmpty
          ? store.firestore.collection(collection).where('shopId', isEqualTo: shopId)
          : store.firestore.collection(collection).where('ownerId', isEqualTo: uid)).limit(100);
      // Products and services are two collections; both are listed, each edited in its own.
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: mine('products').snapshots(),
        builder: (context, productsSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: mine('services').snapshots(),
        builder: (context, servicesSnapshot) {
          final docs = [
            for (final doc in productsSnapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) ('products', doc),
            for (final doc in servicesSnapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              if (doc.data()['kind'] != 'serviceType') ('services', doc),
          ];
          return vendorCard('My products and materials', [
            if (docs.isEmpty) const Text('No published products yet. Submitted products appear here once published.'),
            for (final (collection, doc) in docs)
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
                            toast(vendorPublished(await store.submitVendorChange(type: 'visibility', collection: collection, docId: doc.id, changes: {'active': doc.data()['active'] == false})));
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
                            toast(vendorPublished(await store.submitVendorChange(type: 'price', collection: collection, docId: doc.id, changes: {'price': n.toDouble()})));
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
                            toast(vendorPublished(await store.submitVendorChange(type: 'stock', collection: collection, docId: doc.id, changes: {'stock': n.toInt()})));
                          }),
                  ),
                  IconButton(tooltip: 'Change photo', icon: const Icon(Icons.add_photo_alternate_outlined), onPressed: busy ? null : () => _changePhoto(collection, doc.id)),
                ]),
              ),
          ]);
        },
        ),
      );
    },
  );
}
