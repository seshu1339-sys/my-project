import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';

/// Vendor app: the paid vendor's boxes. Which of their shop photos the website's right-side ad box shows, and how far it reaches (the
/// plan's km). Their Today's Offers box shows their day's offer (Premium screen). Free vendors see that the boxes come with a plan.
class VendorShowcaseSection extends StatelessWidget {
  const VendorShowcaseSection({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final db = store.firestore;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('vendorPremium').doc(uid).snapshots(),
      builder: (context, premium) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('vendorShowcase').doc(uid).snapshots(),
        builder: (context, showcase) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.collection('vendors').doc(uid).snapshots().asyncExpand((v) => db.collection('shops').doc('${v.data()?['shopId'] ?? uid}').snapshots()),
          builder: (context, shop) {
            final p = premium.data?.data();
            final paid = p?['active'] == true;
            final s = shop.data?.data() ?? const <String, dynamic>{};
            final photos = [
              if ('${s['imageUrl'] ?? ''}'.startsWith('http')) '${s['imageUrl']}',
              for (final k in s.keys.where((k) => RegExp(r'^photo\d+Url$').hasMatch(k)).toList()..sort()) if ('${s[k]}'.startsWith('http')) '${s[k]}',
            ];
            return VendorShowcaseView(
              paid: paid,
              radiusKm: (p?['radiusKm'] as num?)?.toDouble(),
              photos: photos,
              chosen: showcase.data?.data()?['photoUrl']?.toString(),
              onChoose: (url) => store.call('chooseShowcasePhoto', {'photoUrl': url}),
            );
          },
        ),
      ),
    );
  }
}

class VendorShowcaseView extends StatelessWidget {
  const VendorShowcaseView({super.key, required this.paid, required this.photos, required this.onChoose, this.chosen, this.radiusKm});
  final bool paid;
  final double? radiusKm;
  final List<String> photos;
  final String? chosen;
  final Future<void> Function(String url) onChoose;

  Future<void> _choose(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await onChoose(url);
      messenger.showSnackBar(const SnackBar(content: Text('Your ad box shows this photo now.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final km = radiusKm == null ? '' : ' within ${radiusKm! == radiusKm!.roundToDouble() ? radiusKm!.toInt() : radiusKm} km';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your ad box and Today\'s Offers box', style: TextStyle(fontWeight: FontWeight.bold)),
          if (!paid)
            const Text('With a Silver, Gold or Premium plan your shop gets a box in Today\'s Offers and in the website\'s ad boxes.', key: ValueKey('showcase-paid-only'))
          else ...[
            Text('Customers$km see your boxes. Tapping one shows your shop, its address and the way there. Your Today\'s Offers box shows your day\'s offer.'),
            const SizedBox(height: 8),
            const Text('Which photo should your ad box show?', style: TextStyle(fontWeight: FontWeight.w600)),
            if (photos.isEmpty) const Text('Add a shop photo first (Shop photos).'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, url) in photos.indexed)
                InkWell(
                  key: ValueKey('showcase-photo-$i'),
                  onTap: () => _choose(context, url),
                  child: Container(
                    width: 96,
                    height: 72,
                    decoration: BoxDecoration(border: Border.all(color: url == chosen ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 3), borderRadius: BorderRadius.circular(8)),
                    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_outlined))),
                  ),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}
