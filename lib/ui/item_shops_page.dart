import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/item_shops.dart';
import 'contact_actions.dart';
import 'design_tokens.dart';
import 'shared.dart';

/// Opens where to buy an item. [openItem] opens one shop's item (the product page), to put it in the bag.
void openItemShops(BuildContext context, Store store, {required String name, String libraryItemId = '', required ValueChanged<Entry> openItem}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemShopsPage(store: store, name: name, libraryItemId: libraryItemId, openItem: openItem)));

/// Opens the route to a shop in the maps app (Google Maps), from the customer's place when it is known.
Future<void> openDirections(BuildContext context, double latitude, double longitude, {double? fromLatitude, double? fromLongitude}) async {
  final uri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '$latitude,$longitude',
    if (fromLatitude != null && fromLongitude != null) 'origin': '$fromLatitude,$fromLongitude',
  });
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) message(context, 'Could not open directions');
  } catch (_) {
    if (context.mounted) message(context, 'Could not open directions');
  }
}

/// Vendor spec section 8: where to buy an item the customer chose. Every shop in the customer's town selling it, on a map (each pin is
/// the shop's small photo with its price) and in a list from the lowest price up (photo, name, price, distance). Tapping a shop shows
/// its photo, address, the route and its phone to call. It follows the catalogue live: a new price or a new shop shows at once.
class ItemShopsPage extends StatelessWidget {
  const ItemShopsPage({super.key, required this.store, required this.name, this.libraryItemId = '', required this.openItem});
  final Store store;
  final String name, libraryItemId;
  final ValueChanged<Entry> openItem;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Where to buy $name')),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final offers = itemOffers(
          store.visibleProducts(),
          store.visible('shops'),
          name: name,
          libraryItemId: libraryItemId,
          pincode: store.pincode,
          latitude: store.latitude,
          longitude: store.longitude,
        );
        final where = store.town.isEmpty ? 'near you' : 'in ${store.town}';
        final mapped = offers.where((o) => o.onMap).toList();
        return ListView(
          key: const ValueKey('item-shops'),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              offers.isEmpty
                  ? 'No shop $where sells $name right now.'
                  : '${{for (final o in offers) o.product.text('shopId', o.product.id)}.length} shop${offers.length == 1 ? '' : 's'} $where • from ${money(offers.first.price)}',
              key: const ValueKey('item-shops-summary'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('Prices are the shops\' own and change live.'),
            const SizedBox(height: 12),
            if (mapped.isNotEmpty) ...[
              ItemShopsMap(offers: mapped, latitude: store.latitude, longitude: store.longitude, onShop: (o) => _showShop(context, o)),
              const SizedBox(height: 12),
            ],
            if (offers.isNotEmpty) Text('Lowest price first', style: Theme.of(context).textTheme.titleSmall),
            for (final (i, offer) in offers.indexed) _OfferTile(key: ValueKey('item-offer-$i'), offer: offer, onTap: () => _showShop(context, offer)),
          ],
        );
      },
    ),
  );

  void _showShop(BuildContext context, ItemOffer offer) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        key: const ValueKey('item-shop-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          if (offer.photo.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              child: Image.network(offer.photo, height: 180, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          const SizedBox(height: 12),
          Text(offer.shopName, style: Theme.of(sheet).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          Text('$name: ${money(offer.price)}${offer.unit.isEmpty ? '' : ' for ${offer.unit}'}', style: Theme.of(sheet).textTheme.titleMedium?.copyWith(color: AppTokens.primary)),
          if (offer.address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(offer.address, key: const ValueKey('item-shop-address'))),
          if (offer.distanceKm != null) Text('${distanceText(offer.distanceKm)} from you'),
          if (offer.phone.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Phone: ${offer.phone}')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (offer.onMap)
                FilledButton.icon(
                  key: const ValueKey('item-shop-directions'),
                  onPressed: () => openDirections(sheet, offer.latitude!, offer.longitude!, fromLatitude: store.latitude, fromLongitude: store.longitude),
                  icon: const Icon(Icons.directions),
                  label: const Text('Directions'),
                ),
              ContactActions(phone: offer.phone, whatsapp: offer.whatsapp),
              TextButton(
                key: const ValueKey('item-shop-open-item'),
                onPressed: () {
                  Navigator.pop(sheet);
                  openItem(offer.product);
                },
                child: const Text('Open the item'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({super.key, required this.offer, required this.onTap});
  final ItemOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 8),
    child: ListTile(
      onTap: onTap,
      leading: _ShopPhoto(url: offer.photo, size: 52),
      title: Text(offer.shopName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([
        '${money(offer.price)}${offer.unit.isEmpty ? '' : ' for ${offer.unit}'}',
        if (offer.distanceKm != null) distanceText(offer.distanceKm),
      ].join(' • ')),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class _ShopPhoto extends StatelessWidget {
  const _ShopPhoto({required this.url, required this.size});
  final String url;
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: url.isEmpty
          ? const ColoredBox(color: Color(0xFFE5E7EB), child: Icon(Icons.storefront_outlined))
          : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFE5E7EB), child: Icon(Icons.storefront_outlined))),
    ),
  );
}

/// The map: a pin per shop, each the shop's small photo with its lowest price for the item; the customer's place as a person pin.
/// Opens fitted to all the pins.
class ItemShopsMap extends StatelessWidget {
  const ItemShopsMap({super.key, required this.offers, required this.onShop, this.latitude, this.longitude, this.height = 320});
  final List<ItemOffer> offers;
  final ValueChanged<ItemOffer> onShop;
  final double? latitude, longitude;
  final double height;

  @override
  Widget build(BuildContext context) {
    // One pin per shop: its cheapest offer (offers come cheapest first).
    final byShop = <String, ItemOffer>{};
    for (final o in offers) {
      byShop.putIfAbsent(o.product.text('shopId', o.product.id), () => o);
    }
    final pins = byShop.values.toList();
    final points = [
      for (final o in pins) LatLng(o.latitude!, o.longitude!),
      if (latitude != null && longitude != null) LatLng(latitude!, longitude!),
    ];
    final fit = points.length > 1 ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(56), maxZoom: 16) : null;
    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppTokens.radiusLg), border: Border.all(color: AppTokens.border)),
        clipBehavior: Clip.antiAlias,
        child: FlutterMap(
          options: MapOptions(initialCenter: points.first, initialZoom: 15, initialCameraFit: fit),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.neighbourly.ecommerce'),
            MarkerLayer(
              markers: [
                if (latitude != null && longitude != null)
                  Marker(point: LatLng(latitude!, longitude!), child: const Icon(Icons.person_pin_circle, color: AppTokens.accentGold, size: 34)),
                for (final o in pins)
                  Marker(
                    point: LatLng(o.latitude!, o.longitude!),
                    width: 84,
                    height: 72,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      key: ValueKey('item-pin-${o.product.text('shopId', o.product.id)}'),
                      onTap: () => onShop(o),
                      child: Tooltip(
                        message: o.shopName,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: AppTokens.shadowSoft),
                              child: _ShopPhoto(url: o.photo, size: 38),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: AppTokens.primary, borderRadius: BorderRadius.circular(10)),
                              child: Text(money(o.price), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [TextSourceAttribution('OpenStreetMap contributors', onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')))],
            ),
          ],
        ),
      ),
    );
  }
}

/// Under the search box while the customer types: the items that match, to choose one ("Tomato • 3 shops • from ₹28").
/// Choosing opens where to buy it.
class ItemSearchChoices extends StatelessWidget {
  const ItemSearchChoices({super.key, required this.store, required this.query, required this.openItem});
  final Store store;
  final String query;
  final ValueChanged<Entry> openItem;

  @override
  Widget build(BuildContext context) {
    final choices = itemChoices(store.visibleProducts(), query, pincode: store.pincode);
    if (choices.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('item-search-choices'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Where to buy:', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final c in choices)
            ActionChip(
              key: ValueKey('item-choice-${itemNameKey(c.name)}'),
              avatar: const Icon(Icons.map_outlined, size: 18),
              label: Text('${c.name} • ${c.shops} shop${c.shops == 1 ? '' : 's'} • from ${money(c.lowest)}'),
              onPressed: () => openItemShops(context, store, name: c.name, libraryItemId: c.libraryItemId, openItem: openItem),
            ),
        ],
      ),
    );
  }
}
