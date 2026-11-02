import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../domain/catalog.dart';
import '../../services/strings.dart';
import '../../ui/screen_view.dart';
import 'offer_model.dart';

/// The customer's Shop Offers page: live offers of the shops around the chosen location, or of every shop while no location is chosen.
class OffersPage extends StatefulWidget {
  const OffersPage({super.key, required this.store, this.onShop});
  final Store store;
  final void Function(BuildContext context, Entry shop)? onShop;

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  Store get store => widget.store;
  bool get located => store.latitude != null || store.pincode.isNotEmpty;

  // Made once, so a rebuild keeps the same listener. Ended offers never come back from the server.
  late final stream = !store.live
      ? null
      : store.firestore.collection('vendorOffers').where('status', isEqualTo: 'live').where('endsAt', isGreaterThan: Timestamp.now()).orderBy('endsAt').limit(300).snapshots();

  Widget _view(List<VendorOffer> offers) {
    final shops = located ? store.nearby() : store.visible('shops');
    return OffersView(
      offers: offersForCustomer(offers, {for (final shop in shops) shop.id}, DateTime.now()),
      located: located,
      onShop: widget.onShop == null
          ? null
          : (offer) {
              final shop = shops.where((s) => s.id == offer.shopId).firstOrNull;
              if (shop != null) widget.onShop!(context, shop);
            },
    );
  }

  @override
  Widget build(BuildContext context) => ScreenView(
    'shop_offers',
    child: Scaffold(
      appBar: AppBar(title: Text('Shop Offers'.tr(context))),
      body: stream == null
          ? _view(const [])
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Offers could not load.'.tr(context)));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                return _view([for (final doc in snapshot.data!.docs) VendorOffer.fromData(doc.id, doc.data())]);
              },
            ),
    ),
  );
}

/// The offers as cards. Tapping one shows all its photos and details.
class OffersView extends StatelessWidget {
  const OffersView({super.key, required this.offers, required this.located, this.onShop});
  final List<VendorOffer> offers;
  final bool located;
  final void Function(VendorOffer offer)? onShop;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text((located ? 'No offers near you right now.' : 'No offers right now.').tr(context), key: const ValueKey('offers-empty'), textAlign: TextAlign.center),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisExtent: 270, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: offers.length,
      itemBuilder: (context, i) => _OfferCard(offer: offers[i], onShop: onShop),
    );
  }
}

Widget offerPhoto(String url, {double? width, double? height}) => Image.network(
  url,
  width: width,
  height: height,
  fit: BoxFit.cover,
  errorBuilder: (_, _, _) => SizedBox(width: width, height: height, child: const Icon(Icons.image_not_supported_outlined)),
);

class _Prices extends StatelessWidget {
  const _Prices(this.offer);
  final VendorOffer offer;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
    Text(offerPriceText(offer.offerPrice), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
    if (offer.regularPrice != null) Text(offerPriceText(offer.regularPrice!), style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.black54)),
  ]);
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.onShop});
  final VendorOffer offer;
  final void Function(VendorOffer offer)? onShop;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('offer-${offer.id}'),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => showDialog<void>(context: context, builder: (_) => _OfferDetails(offer: offer, onShop: onShop)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: SizedBox(width: double.infinity, child: offer.photos.isEmpty ? const Icon(Icons.local_offer_outlined) : offerPhoto(offer.photos.first))),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(offer.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            _Prices(offer),
            Text(offer.shopName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ]),
    ),
  );
}

class _OfferDetails extends StatelessWidget {
  const _OfferDetails({required this.offer, required this.onShop});
  final VendorOffer offer;
  final void Function(VendorOffer offer)? onShop;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(offer.title),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final url in offer.photos) Padding(padding: const EdgeInsets.only(bottom: 8), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: offerPhoto(url))),
          _Prices(offer),
          if (offer.details.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(offer.details)),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(offer.shopName, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (offer.endsAt != null) Text('${'Offer ends'.tr(context)}: ${offerDate(offer.endsAt!)}'),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text('Close'.tr(context))),
      if (onShop != null)
        FilledButton(
          key: const ValueKey('offer-open-shop'),
          onPressed: () {
            Navigator.pop(context);
            onShop!(offer);
          },
          child: Text('Open shop'.tr(context)),
        ),
    ],
  );
}
