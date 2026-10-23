import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'vendor_section_kit.dart';

/// Special Category Exclusives: shown only to vendors the admin switched it on for; its own form, lists and busy flag.
class VendorExclusivesSection extends StatelessWidget {
  const VendorExclusivesSection({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendors').doc(uid).snapshots(),
    builder: (_, vendor) => vendor.data?.data()?['specialCategoryExclusives'] != true
        ? const SizedBox.shrink()
        : _ExclusivesCard(store: store, uid: uid, maxDays: (vendor.data?.data()?['exclusivesMaxDurationDays'] as num?)?.toInt() ?? 0),
  );
}

class _ExclusivesCard extends StatefulWidget {
  const _ExclusivesCard({required this.store, required this.uid, required this.maxDays});
  final Store store;
  final String uid;
  final int maxDays;
  @override
  State<_ExclusivesCard> createState() => _ExclusivesCardState();
}

class _ExclusivesCardState extends State<_ExclusivesCard> with VendorSectionState {
  final name = TextEditingController(), price = TextEditingController(), duration = TextEditingController();
  String? imageUrl;
  Uint8List? imageBytes;
  Store get store => widget.store;
  String get uid => widget.uid;

  @override
  void dispose() {
    for (final c in [name, price, duration]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxDays = widget.maxDays;
    return vendorCard('Special Category Exclusives', [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Item or design name')),
      TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
      TextField(controller: duration, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Active duration in days (up to $maxDays)')),
      const SizedBox(height: 8),
      if (imageBytes != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(imageBytes!, height: 120, fit: BoxFit.cover)),
      Wrap(spacing: 8, children: [
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
          label: const Text('Upload photo'),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () => run(() async {
                  final p = double.tryParse(price.text.trim());
                  final days = int.tryParse(duration.text.trim());
                  if (name.text.trim().length < 2) throw StateError('Enter a name for the item.');
                  if (p == null || p < 0) throw StateError('Enter a valid price.');
                  if (days == null || days < 1) throw StateError('Enter the active duration in days.');
                  if (imageUrl == null) throw StateError('Upload a photo first.');
                  await store.call('submitExclusiveItem', {'name': name.text.trim(), 'price': p, 'imageUrl': imageUrl, 'durationDays': days});
                  for (final c in [name, price, duration]) {
                    c.clear();
                  }
                  setState(() {
                    imageUrl = null;
                    imageBytes = null;
                  });
                  toast('Exclusive item published');
                }),
          child: const Text('Publish exclusive item'),
        ),
      ]),
      const SizedBox(height: 12),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('products').where('ownerId', isEqualTo: uid).where('isExclusive', isEqualTo: true).where('active', isEqualTo: true).snapshots(),
        builder: (context, snapshot) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Active exclusives', style: Theme.of(context).textTheme.titleSmall),
          for (final doc in snapshot.data?.docs ?? const [])
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${doc.data()['name']}'),
              subtitle: Text('₹${doc.data()['price']} • expires ${(doc.data()['expiresAt'] ?? '').toString().substring(0, 10)}'),
            ),
          if ((snapshot.data?.docs ?? const []).isEmpty) const Text('No active exclusive items yet.'),
        ]),
      ),
      const SizedBox(height: 8),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('products').where('ownerId', isEqualTo: uid).where('isExclusive', isEqualTo: true).where('active', isEqualTo: false).snapshots(),
        builder: (context, snapshot) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Archived (reactivate within 15 days)', style: Theme.of(context).textTheme.titleSmall),
          for (final doc in snapshot.data?.docs ?? const [])
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${doc.data()['name']}'),
              subtitle: Text('₹${doc.data()['price']}'),
              trailing: OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        final days = await askVendorNumber(context, 'Reactivate item', 'Active duration in days (up to $maxDays)', integer: true);
                        if (days == null) return;
                        await store.call('reactivateExclusiveItem', {'productId': doc.id, 'durationDays': days.toInt()});
                        toast('Item reactivated');
                      }),
                child: const Text('Reactivate'),
              ),
            ),
          if ((snapshot.data?.docs ?? const []).isEmpty) const Text('Nothing archived right now.'),
        ]),
      ),
    ]);
  }
}
