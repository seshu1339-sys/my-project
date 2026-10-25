import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'quick_add.dart';
import 'vendor_ads_page.dart';
import 'vendor_section_exclusives.dart';
import 'vendor_section_kit.dart';
import 'vendor_section_orders.dart';
import 'vendor_section_products.dart';
import 'vendor_section_requests.dart';
import 'vendor_section_shop_ad.dart';
import 'vendor_section_shop_photos.dart';

/// Business features. Only built once the application status is approved; the
/// server independently refuses every one of these actions for anyone else.
///
/// This page only lays the sections out, in order. Each section is its own widget (vendor_section_*.dart) with its own state, its own busy
/// flag and its own data streams, so changing, removing or breaking one never touches another.
class VendorWorkspace extends StatelessWidget {
  const VendorWorkspace({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

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
    QuickAddHome(store: store),
    const SizedBox(height: 20),
    VendorShopPhotosSection(store: store, uid: uid),
    VendorShopAdSection(store: store, uid: uid),
    VendorMyAdsCard(store: store, uid: uid),
    const SizedBox(height: 20),
    VendorAddProductSection(store: store, uid: uid),
    // The vendor's own shop's products (including ones the office added for the shop), not only the ones the vendor submitted itself.
    VendorMyProductsSection(store: store, uid: uid),
    VendorChangeRequestSection(store: store, uid: uid),
    VendorVerifyPurchaseSection(store: store),
    VendorExclusivesSection(store: store, uid: uid),
    VendorOrdersSection(store: store, uid: uid),
    VendorChangeHistorySection(store: store, uid: uid),
  ]);
}

/// The "My Ads" entry card.
class VendorMyAdsCard extends StatelessWidget {
  const VendorMyAdsCard({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  Widget build(BuildContext context) => vendorCard('My Ads', [
    FilledButton.icon(
      key: const ValueKey('open-my-ads'),
      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => VendorAdsPage(store: store, uid: uid))),
      icon: const Icon(Icons.campaign_outlined),
      label: const Text('Open My Ads'),
    ),
  ], note: 'Send an ad for your shop, see if it is live, how many days are left and how many people saw it. Every ad is checked by the administrator before it goes live.');
}
