import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/shop_ads.dart';
import '../services/shop_ad_payment.dart';
import 'vendor_section_kit.dart';

/// "Ad for your shop": the vendor ticks that they want an ad; the office arranges it offline ([payment]) and puts it in a Right Side
/// Ad Box of the website. Then the vendor sees their ad and its total views since it started (not who is watching now).
/// This section only needs the store and the vendor id.
class VendorShopAdSection extends StatelessWidget {
  const VendorShopAdSection({super.key, required this.store, required this.uid, this.payment = const OfflineShopAdPayment()});
  final Store store;
  final String uid;
  final ShopAdPayment payment;

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendors').doc(uid).snapshots(),
    builder: (context, vendor) => StreamBuilder<List<Entry>>(
      stream: store.watchEntries('rightBoxAds', vendorId: uid),
      builder: (context, ads) => StreamBuilder<List<Entry>>(
        stream: store.watchEntries('adStats', vendorId: uid),
        builder: (context, stats) => ShopAdView(
          interested: vendor.data?.data()?['adInterest'] == true,
          ads: shopAdsInOrder(ads.data ?? const []),
          views: shopAdViews(stats.data ?? const []),
          payment: payment,
          onInterest: store.setAdInterest,
        ),
      ),
    ),
  );
}

/// The card itself: the tick, what happens next, the live ad with its total views, and earlier ads.
class ShopAdView extends StatefulWidget {
  const ShopAdView({super.key, required this.interested, required this.ads, required this.views, required this.onInterest, this.payment = const OfflineShopAdPayment()});
  final bool interested;
  final List<ShopAd> ads;
  final Map<String, int> views;
  final Future<void> Function(bool interested) onInterest;
  final ShopAdPayment payment;
  @override
  State<ShopAdView> createState() => _ShopAdViewState();
}

class _ShopAdViewState extends State<ShopAdView> {
  // What the tick shows while the server is saving it.
  bool? saving;

  Future<void> _tick(bool value) async {
    setState(() => saving = value);
    try {
      await widget.onInterest(value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value ? 'Thank you. Our office will contact you about your ad.' : 'Saved: you do not want an ad now.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.ads.where((a) => a.live).toList();
    final ended = widget.ads.where((a) => !a.live).take(3).toList();
    final interested = saving ?? widget.interested;
    final payLabel = widget.payment.payLabel;
    return vendorCard('Ad for your shop', [
      CheckboxListTile(
        key: const ValueKey('shop-ad-interest'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: interested,
        onChanged: saving != null ? null : (v) => _tick(v ?? false),
        title: const Text('I want an ad for my shop'),
      ),
      if (interested && live.isEmpty) ...[
        Text(widget.payment.howItWorks, key: const ValueKey('shop-ad-how')),
        if (payLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(key: const ValueKey('shop-ad-pay'), onPressed: () => widget.payment.pay(context), child: Text(payLabel)),
          ),
      ],
      for (final ad in live) _live(context, ad),
      if (ended.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Earlier ads', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final ad in ended)
          Text(
            '${shopAdDate(ad.startedAt)} to ${shopAdDate(ad.endedAt)}: ${shopAdCount(widget.views[ad.id] ?? 0)} views',
            key: ValueKey('shop-ad-ended-${ad.id}'),
          ),
      ],
    ], note: 'Put an ad for your shop in the boxes on the right side of the website. Ads are arranged by our office for now.');
  }

  Widget _live(BuildContext context, ShopAd ad) {
    final since = shopAdDate(ad.startedAt);
    return Container(
      key: ValueKey('shop-ad-live-${ad.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.campaign_outlined, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your ad is live on the website', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              shopAdCount(widget.views[ad.id] ?? 0),
              key: ValueKey('shop-ad-views-${ad.id}'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(since.isEmpty ? 'total views since your ad started' : 'total views since $since, when your ad started'),
          ]),
        ),
      ]),
    );
  }
}
