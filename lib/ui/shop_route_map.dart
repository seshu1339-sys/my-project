import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/catalog.dart';
import '../domain/item_shops.dart';
import '../services/customer_position.dart';
import '../services/road_route.dart';
import '../services/usage.dart';
import 'contact_actions.dart';
import 'design_tokens.dart';
import 'item_shops_page.dart';
import 'shared.dart';

/// One shop to show on the map: who it is, where, how to reach it, and the item (and its price) the customer came for.
class ShopStop {
  const ShopStop({
    required this.shopId,
    required this.name,
    this.photo = '',
    this.address = '',
    this.phone = '',
    this.whatsapp = '',
    this.town = '',
    this.latitude,
    this.longitude,
    this.itemName = '',
    this.itemPhoto = '',
    this.price,
    this.unit = '',
  });
  final String shopId, name, photo, address, phone, whatsapp, town, itemName, itemPhoto, unit;
  final double? latitude, longitude, price;
  bool get onMap => latitude != null && longitude != null;

  /// A shop of the item's shop list (lib/domain/item_shops.dart).
  factory ShopStop.offer(ItemOffer o, {required String itemName}) => ShopStop(
    shopId: o.product.text('shopId', o.product.id),
    name: o.shopName,
    photo: o.shop?.text('imageUrl') ?? '',
    address: o.address,
    phone: o.phone,
    whatsapp: o.whatsapp,
    town: o.shop?.text('town') ?? '',
    latitude: o.latitude,
    longitude: o.longitude,
    itemName: itemName,
    itemPhoto: o.product.text('imageUrl'),
    price: o.price,
    unit: o.unit,
  );

  /// A shop from its record, for an item at [price].
  factory ShopStop.shop(Entry? shop, {required String shopId, String itemName = '', String itemPhoto = '', double? price, String unit = ''}) {
    double? at(String key) => shop?.data[key] is num && shop!.data[key] != 0 ? (shop.data[key] as num).toDouble() : null;
    return ShopStop(
      shopId: shopId,
      name: shop?.text('name', 'Shop') ?? 'Shop',
      photo: shop?.text('imageUrl') ?? '',
      address: shop?.text('address') ?? '',
      phone: shop?.text('phone') ?? '',
      whatsapp: shop?.text('whatsapp') ?? '',
      town: shop?.text('town') ?? '',
      latitude: at('latitude'),
      longitude: at('longitude'),
      itemName: itemName,
      itemPhoto: itemPhoto,
      price: price,
      unit: unit,
    );
  }
}

/// Opens the shop on a map straight away (no page in between): where it is, the road from the customer, its phone and photo.
Future<void> showShopRoute(BuildContext context, ShopStop stop) =>
    Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ShopRouteView(stop: stop)));

class ShopRouteView extends StatefulWidget {
  const ShopRouteView({super.key, required this.stop, this.route = roadRoute});
  final ShopStop stop;
  // Test seam: how the road is found.
  final Future<RoadRoute> Function(LatLng from, LatLng to) route;
  @override
  State<ShopRouteView> createState() => _ShopRouteViewState();
}

class _ShopRouteViewState extends State<ShopRouteView> {
  final map = MapController();
  LatLon? me = CustomerPosition.known;
  RoadRoute? road;
  bool finding = true;
  ShopStop get stop => widget.stop;

  @override
  void initState() {
    super.initState();
    Usage.screen('shop_route');
    _findWay();
  }

  Future<void> _findWay({bool again = false}) async {
    setState(() => finding = true);
    me = await CustomerPosition.find(again: again);
    if (me != null && stop.onMap) {
      final r = await widget.route(LatLng(me!.latitude, me!.longitude), LatLng(stop.latitude!, stop.longitude!));
      if (!mounted) return;
      setState(() => road = r);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
    if (mounted) setState(() => finding = false);
  }

  void _fit() {
    final points = [if (stop.onMap) LatLng(stop.latitude!, stop.longitude!), if (me != null) LatLng(me!.latitude, me!.longitude), ...?road?.points];
    if (points.length < 2) return;
    try {
      map.fitCamera(CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48), maxZoom: 17));
    } catch (_) {
      /* the map is not on screen yet */
    }
  }

  void _track(String event) => Usage.track(event, key: stop.shopId, label: stop.name, town: stop.town);

  Widget _map() {
    final shop = LatLng(stop.latitude!, stop.longitude!);
    return FlutterMap(
      key: const ValueKey('shop-route-map'),
      mapController: map,
      options: MapOptions(initialCenter: shop, initialZoom: 15, onMapReady: _fit),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.neighbourly.ecommerce'),
        if (road != null) PolylineLayer(polylines: [Polyline(points: road!.points, color: const Color(0xFF2563EB), strokeWidth: 5)]),
        MarkerLayer(
          markers: [
            if (me != null) Marker(point: LatLng(me!.latitude, me!.longitude), child: const Icon(Icons.person_pin_circle, color: AppTokens.accentGold, size: 38)),
            Marker(
              point: shop,
              width: 64,
              height: 64,
              alignment: Alignment.topCenter,
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: AppTokens.shadowSoft),
                child: _CirclePhoto(url: stop.photo.isNotEmpty ? stop.photo : stop.itemPhoto, size: 52, icon: Icons.storefront_outlined),
              ),
            ),
          ],
        ),
        RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors', onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')))],
        ),
      ],
    );
  }

  Widget _details(BuildContext context) {
    final theme = Theme.of(context);
    final distance = me == null || !stop.onMap ? null : distanceKm(me!.latitude, me!.longitude, stop.latitude!, stop.longitude!);
    final byRoad = road == null ? '' : roadRouteText(road!);
    return ListView(
      key: const ValueKey('shop-route-details'),
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      children: [
        Row(
          children: [
            _CirclePhoto(url: stop.photo, size: 64, icon: Icons.storefront_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stop.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  if (stop.itemName.isNotEmpty && stop.price != null)
                    Text(
                      '${stop.itemName}: ${money(stop.price!)}${stop.unit.isEmpty ? '' : ' / ${stop.unit}'}',
                      key: const ValueKey('shop-route-price'),
                      style: theme.textTheme.titleMedium?.copyWith(color: AppTokens.primary, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (stop.address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(stop.address)),
        if (byRoad.isNotEmpty || distance != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(byRoad.isNotEmpty ? byRoad : '${distanceText(distance)} from you', key: const ValueKey('shop-route-distance')),
          ),
        if (finding) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Finding the way...')),
        if (!finding && me == null && stop.onMap)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton.icon(
              key: const ValueKey('shop-route-locate'),
              onPressed: () => _findWay(again: true),
              icon: const Icon(Icons.my_location),
              label: const Text('Show the way from my location'),
            ),
          ),
        if (!stop.onMap) const Padding(padding: EdgeInsets.only(top: 6), child: Text('This shop has not shared its location on the map yet.')),
        if (stop.phone.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Phone: ${stop.phone}', key: const ValueKey('shop-route-phone'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            ContactActions(phone: stop.phone, whatsapp: stop.whatsapp, onUsed: (way) => _track(way == 'call' ? 'shop_call' : 'shop_whatsapp')),
            if (stop.onMap)
              OutlinedButton.icon(
                key: const ValueKey('shop-route-directions'),
                onPressed: () {
                  _track('shop_directions');
                  openDirections(context, stop.latitude!, stop.longitude!, fromLatitude: me?.latitude, fromLongitude: me?.longitude);
                },
                icon: const Icon(Icons.directions),
                label: const Text('Directions'),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(stop.name)),
    body: LayoutBuilder(
      builder: (context, c) {
        final mapView = stop.onMap ? _map() : const ColoredBox(color: Color(0xFFE5E7EB), child: Center(child: Icon(Icons.location_off_outlined, size: 48)));
        if (c.maxWidth >= 900) {
          return Row(children: [Expanded(child: mapView), SizedBox(width: 380, child: _details(context))]);
        }
        return Column(children: [Expanded(child: mapView), ConstrainedBox(constraints: BoxConstraints(maxHeight: c.maxHeight * .5), child: _details(context))]);
      },
    ),
  );
}

class _CirclePhoto extends StatelessWidget {
  const _CirclePhoto({required this.url, required this.size, required this.icon});
  final String url;
  final double size;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: url.isEmpty
          ? ColoredBox(color: const Color(0xFFE5E7EB), child: Icon(icon))
          : ProductArt(Entry('photo', {'imageUrl': url}), height: size, width: size),
    ),
  );
}
