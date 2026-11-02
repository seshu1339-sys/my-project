import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/offerstore/offerstore_module.dart';
import 'shop_page.dart';

/// Hands the running vendor offers to the home page. With no connection, or if they cannot be read, there are none and the boxes go on as usual.
class VendorOffersFeed extends StatefulWidget {
  const VendorOffersFeed({super.key, required this.store, required this.builder, this.source});
  final Store store;
  final Widget Function(BuildContext context, List<TodaysOffer> offers) builder;

  /// Where the offers come from; the offer store unless a test gives another.
  final Stream<List<TodaysOffer>>? source;

  @override
  State<VendorOffersFeed> createState() => _VendorOffersFeedState();
}

class _VendorOffersFeedState extends State<VendorOffersFeed> {
  late final stream = widget.source ?? (widget.store.live ? FirestoreTodaysOfferStore(widget.store).watchLive() : null);

  @override
  Widget build(BuildContext context) {
    if (stream == null) return widget.builder(context, const []);
    return StreamBuilder<List<TodaysOffer>>(
      stream: stream,
      builder: (context, snapshot) => widget.builder(context, snapshot.data ?? const []),
    );
  }
}

/// The offers this customer may see: running, from a shop inside the customer's circle (the same rule as Nearby shops, so a hidden shop or an
/// unknown location shows none), the earliest submitted first.
List<TodaysOffer> vendorOffersForCustomer(List<TodaysOffer> offers, Set<String> nearbyShopIds, DateTime now) =>
    [for (final offer in offers) if (offer.liveAt(now) && nearbyShopIds.contains(offer.shopId)) offer]
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));

/// A tap on a vendor's box goes straight to that shop's page.
void openVendorOfferShop(BuildContext context, Store store, TodaysOffer offer) {
  final shop = store.entries('shops').where((s) => s.id == offer.shopId).firstOrNull;
  if (shop != null) Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShopPage(store: store, shop: shop)));
}
