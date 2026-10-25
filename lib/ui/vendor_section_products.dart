import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/vendor_items.dart';
import 'library_item_tile.dart';
import 'vendor_section_kit.dart';

/// "Add an item": the vendor picks a category, then one of the admin's items (photo and name come with it, nothing is typed), the
/// quantity (1-10 kg or 1-10 pieces) and the price for that quantity. Saved items go live at once at the vendor's location. A vendor
/// has [vendorItemLimit] items (2 unless the admin allows more; hidden items count): "Add another item" shows only below the limit.
/// Photo 1 of the shop is required first. Its own state and busy flag.
class VendorAddProductSection extends StatefulWidget {
  const VendorAddProductSection({super.key, required this.store, required this.uid, this.preview});
  final Store store;
  final String uid;

  /// For tests: (items the vendor has, items allowed, photo 1 ready) instead of reading them from Firestore.
  final (int, int, bool)? preview;
  @override
  State<VendorAddProductSection> createState() => _VendorAddProductSectionState();
}

class _VendorAddProductSectionState extends State<VendorAddProductSection> with VendorSectionState {
  final price = TextEditingController();
  String? categoryId;
  Entry? item;
  String unitType = 'kg';
  int quantity = 1;
  // The form opens by itself while the vendor has no item yet; afterwards "Add another item" opens it.
  bool? adding;
  Store get store => widget.store;
  String get uid => widget.uid;

  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  void _reset() {
    price.clear();
    categoryId = null;
    item = null;
    unitType = 'kg';
    quantity = 1;
  }

  Future<void> _save() async {
    final chosen = item;
    if (chosen == null) throw StateError('Choose an item.');
    final p = double.tryParse(price.text.trim());
    if (p == null || p <= 0) throw StateError('Enter the price for ${vendorItemUnit(unitType, quantity)}.');
    await store.submitVendorChange(type: 'newProduct', collection: 'products', docId: '', changes: {
      'libraryItemId': chosen.id, 'unitType': unitType, 'quantity': quantity, 'price': p,
    });
    setState(() {
      _reset();
      adding = false;
    });
    toast('Saved. Your item is live at your shop\'s location.');
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    if (preview != null) return _card(context, itemCount: preview.$1, itemLimit: preview.$2, shopPhotoReady: preview.$3);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('vendors').doc(uid).snapshots(),
      builder: (context, vendor) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('products').where('ownerId', isEqualTo: uid).snapshots(),
        builder: (context, mine) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          // Photo 1 (the shop itself) is required before items can be added; it may still be waiting for the admin.
          stream: store.firestore.collection('vendorShopPhotos').doc('${uid}_1').snapshots(),
          builder: (context, photo) => _card(
            context,
            itemCount: mine.data?.size ?? 0,
            itemLimit: vendorItemLimit(vendor.data?.data()),
            shopPhotoReady: const ['pending', 'approved'].contains(photo.data?.data()?['status']),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, {required int itemCount, required int itemLimit, required bool shopPhotoReady}) {
    final full = itemCount >= itemLimit;
    final open = !full && (adding ?? itemCount == 0);
    final library = store.entries('productImageLibrary');
    final categories = libraryCategories(library, store.visible('categories'));
    final items = categoryId == null ? const <Entry>[] : libraryItemsIn(library, categoryId!);
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return vendorCard('Add an item', [
      Text('Items: $itemCount of $itemLimit', key: const ValueKey('vendor-item-count'), style: const TextStyle(fontWeight: FontWeight.bold)),
      if (!shopPhotoReady) Text('Add photo 1, a photo of your shop (Shop photos above), first: it is required before you add items.', key: const ValueKey('shop-photo-required'), style: error),
      if (full)
        Text('You have $itemLimit item${itemLimit == 1 ? '' : 's'}, your limit. Ask the admin for permission to add more.', key: const ValueKey('vendor-item-limit-reached'))
      else if (!open)
        FilledButton.icon(
          key: const ValueKey('vendor-add-another'),
          onPressed: busy || !shopPhotoReady ? null : () => setState(() => adding = true),
          icon: const Icon(Icons.add),
          label: Text(itemCount == 0 ? 'Add an item' : 'Add another item'),
        )
      else ...[
        DropdownButtonFormField<String>(
          key: ValueKey('vendor-item-category-$categoryId'),
          initialValue: categoryId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [for (final c in categories) DropdownMenuItem(value: c.$1, child: Text(c.$2))],
          onChanged: (v) => setState(() {
            categoryId = v;
            item = null;
          }),
        ),
        if (categories.isEmpty) const Text('The admin has not added any items yet. Please check again later.'),
        if (categoryId != null) ...[
          const SizedBox(height: 8),
          const Text('Choose your item:'),
          if (items.isEmpty) const Text('No items in this category yet.'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in items)
                LibraryItemTile(
                  key: ValueKey('vendor-library-item-${e.id}'),
                  item: e,
                  selected: item?.id == e.id,
                  onTap: () => setState(() => item = e),
                ),
            ],
          ),
        ],
        if (item != null) ...[
          const SizedBox(height: 12),
          SegmentedButton<String>(
            key: const ValueKey('vendor-item-unit'),
            segments: const [ButtonSegment(value: 'kg', label: Text('Kg')), ButtonSegment(value: 'pcs', label: Text('Pieces'))],
            selected: {unitType},
            onSelectionChanged: (v) => setState(() => unitType = v.first),
          ),
          DropdownButtonFormField<int>(
            key: ValueKey('vendor-item-quantity-$unitType'),
            initialValue: quantity,
            decoration: InputDecoration(labelText: unitType == 'kg' ? 'Quantity (kg)' : 'Quantity (pieces)'),
            items: [for (final q in vendorItemQuantities) DropdownMenuItem(value: q, child: Text(vendorItemUnit(unitType, q)))],
            onChanged: (v) => setState(() => quantity = v ?? 1),
          ),
          TextField(
            key: const ValueKey('vendor-item-price'),
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Price for ${vendorItemUnit(unitType, quantity)} (₹)', hintText: 'e.g. 50'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('vendor-item-save'),
            onPressed: busy || !shopPhotoReady ? null : () => run(_save),
            child: const Text('Save'),
          ),
        ],
        if (itemCount > 0)
          TextButton(
            onPressed: () => setState(() {
              _reset();
              adding = false;
            }),
            child: const Text('Cancel'),
          ),
      ],
    ], note: 'Choose from the items the admin has added; you only set the quantity and your price. Your item goes live at your shop\'s location as soon as you save it. A price stays for $vendorPriceValidHours hours; then it is removed and you enter a new price.');
  }
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
                // Prices last 24 hours: an expired one is shown in red until the vendor enters a new price.
                subtitle: Text(
                  '${vendorPriceLine(doc.data(), DateTime.now())} • Stock ${doc.data()['stock'] ?? 0}${doc.data()['active'] == false ? ' • Hidden from customers' : ''}',
                  key: ValueKey('vendor-price-line-${doc.id}'),
                  style: vendorPriceExpired(doc.data(), DateTime.now()) ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
                ),
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
                    tooltip: vendorPriceExpired(doc.data(), DateTime.now()) ? 'Enter a new price' : 'Update price',
                    icon: const Icon(Icons.sell_outlined),
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final n = await askVendorNumber(context, 'Update price', '${doc.data()['unit'] ?? ''}'.isEmpty ? 'New price' : 'New price for ${doc.data()['unit']}', integer: false, initial: '${doc.data()['price'] ?? ''}');
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
