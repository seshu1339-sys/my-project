import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'vendor_section_kit.dart';

/// Shop photos: up to the admin's limit per vendor, each held for review. This section only needs the store and the vendor id.
class VendorShopPhotosSection extends StatefulWidget {
  const VendorShopPhotosSection({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;
  @override
  State<VendorShopPhotosSection> createState() => _VendorShopPhotosSectionState();
}

class _VendorShopPhotosSectionState extends State<VendorShopPhotosSection> with VendorSectionState {
  Store get store => widget.store;
  String get uid => widget.uid;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendorShopPhotos').where('vendorId', isEqualTo: uid).snapshots(),
    builder: (context, snapshot) {
      final bySlot = <int, Map<String, dynamic>>{
        for (final doc in snapshot.data?.docs ?? const []) (doc.data()['slot'] as num).toInt(): doc.data(),
      };
      // Admin-configurable (settings/business.vendorPhotoLimit), default 2 — the limit this app has always had.
      final limit = store.business.number('vendorPhotoLimit', 2).round().clamp(1, 9);
      return vendorCard('Shop photos', [
        Wrap(spacing: 16, runSpacing: 12, children: [for (var slot = 1; slot <= limit; slot++) _slot(slot, bySlot[slot])]),
      ], note: 'Up to $limit photo${limit == 1 ? '' : 's'} of your shop. Each stays pending until the administrator approves it, and is hidden from customers until then.');
    },
  );

  Widget _slot(int slot, Map<String, dynamic>? data) {
    final status = data?['status'] as String?;
    final path = data?['path'] as String?;
    final reason = (data?['decisionReason'] ?? '').toString();
    return SizedBox(
      width: 160,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: path == null
              ? Container(width: 160, height: 120, color: Colors.black12, child: const Icon(Icons.storefront_outlined))
              : FutureBuilder<String>(
                  future: FirebaseStorage.instance.ref(path).getDownloadURL(),
                  builder: (context, snap) => snap.hasData
                      ? Image.network(snap.data!, width: 160, height: 120, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined))
                      : Container(width: 160, height: 120, color: Colors.black12),
                ),
        ),
        const SizedBox(height: 4),
        Text(switch (status) {
          'pending' => 'Pending admin review',
          'approved' => 'Approved',
          'rejected' => 'Rejected${reason.isEmpty ? '' : ': $reason'}',
          _ => 'Empty slot',
        }),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => run(() async {
                  final file = await vendorPickImage();
                  if (file == null) return;
                  await store.uploadShopPhoto(slot, file);
                  await store.call('submitShopPhoto', {'slot': slot});
                  toast('Photo submitted for admin review');
                }),
          child: Text(path == null ? 'Upload' : 'Replace'),
        ),
      ]),
    );
  }
}
