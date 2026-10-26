import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/item_shops.dart';
import '../services/customer_position.dart';
import '../services/usage.dart';
import 'item_shops_page.dart';
import 'shop_route_map.dart';

/// The item page's list of every shop in the town selling the item: name, price and how far from the customer (their location is
/// asked once a visit; without it the list has no distances). Tapping a shop opens it on the map with the road, its phone and photo.
class ItemShopList extends StatefulWidget {
  const ItemShopList({super.key, required this.store, required this.name, this.libraryItemId = ''});
  final Store store;
  final String name, libraryItemId;
  @override
  State<ItemShopList> createState() => _ItemShopListState();
}

class _ItemShopListState extends State<ItemShopList> {
  LatLon? me = CustomerPosition.known;
  bool locating = false;

  @override
  void initState() {
    super.initState();
    if (me == null) _locate();
  }

  Future<void> _locate({bool again = false}) async {
    setState(() => locating = true);
    final found = await CustomerPosition.find(again: again);
    if (mounted) {
      setState(() {
        me = found;
        locating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final offers = itemOffers(
        store.visibleProducts(),
        store.visible('shops'),
        name: widget.name,
        libraryItemId: widget.libraryItemId,
        pincode: store.pincode,
        latitude: me?.latitude,
        longitude: me?.longitude,
      );
      final shops = {for (final o in offers) o.product.text('shopId', o.product.id)}.length;
      return Column(
        key: const ValueKey('item-shop-list'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            offers.isEmpty ? 'No shop near you sells this right now.' : 'Shops selling this ($shops)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (offers.isNotEmpty && me == null)
            Align(
              alignment: Alignment.centerLeft,
              child: locating
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Finding your location...'))
                  : TextButton.icon(
                      key: const ValueKey('item-shops-locate'),
                      onPressed: () => _locate(again: true),
                      icon: const Icon(Icons.my_location),
                      label: const Text('Turn on location to see how far each shop is'),
                    ),
            ),
          for (final (i, offer) in offers.indexed)
            ItemOfferTile(
              key: ValueKey('item-shop-$i'),
              offer: offer,
              onTap: () {
                Usage.button('item_shop_map', label: offer.shopName);
                showShopRoute(context, ShopStop.offer(offer, itemName: widget.name));
              },
            ),
        ],
      );
    },
  );
}
