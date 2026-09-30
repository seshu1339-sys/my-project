import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/geocoding.dart';
import '../services/location.dart';
import 'details.dart';
import 'location_picker.dart';
import 'shared.dart';
import 'shop_map.dart';

/// A shop, joined with one of its products, at a known distance from the
/// customer — the unit both the map markers and the list rows are built from.
class _Match {
  const _Match(this.shop, this.product, this.distanceKm);
  final Entry shop, product;
  final double distanceKm;
}

/// Location-based product search: a radius slider (snapping to admin-defined
/// presets, never typed) plus a map + list of matching products, joined via
/// each product's `shopId` to its shop's mandatory latitude/longitude.
///
/// Prices are always shown for every match — this has nothing to do with,
/// and must never be confused with, `promotionMatchesLocation` (ad
/// geo-targeting, a separate concern).
class ProductSearchPage extends StatefulWidget {
  const ProductSearchPage({super.key, required this.store});
  final Store store;
  @override
  State<ProductSearchPage> createState() => _ProductSearchPageState();
}

class _ProductSearchPageState extends State<ProductSearchPage> {
  Store get store => widget.store;
  bool locating = false;
  String? locationError;
  int presetIndex = 0;
  List<double> presets = const [2, 5, 10, 25, 50];

  @override
  void initState() {
    super.initState();
    _loadPresets();
    if (store.latitude == null) {
      _useGps();
    }
  }

  void _loadPresets() {
    final raw = store.business
        .text('searchRadiusPresetsKm', '2,5,10,25,50')
        .split(',')
        .map((s) => double.tryParse(s.trim()))
        .whereType<double>()
        .where((v) => v > 0)
        .toList()
      ..sort();
    final maxKm = store.business.number('searchRadiusMaxKm', raw.isEmpty ? 50 : raw.last);
    final bounded = raw.where((v) => v <= maxKm).toList();
    presets = bounded.isEmpty ? [maxKm > 0 ? maxKm : 50] : bounded;
    final defaultKm = store.business.number('searchRadiusDefaultKm', presets.first);
    var closest = 0;
    for (var i = 1; i < presets.length; i++) {
      if ((presets[i] - defaultKm).abs() < (presets[closest] - defaultKm).abs()) {
        closest = i;
      }
    }
    presetIndex = closest;
  }

  Future<void> _useGps() async {
    setState(() {
      locating = true;
      locationError = null;
    });
    try {
      final position = await currentPosition(action: 'search nearby products');
      await store.setLocation(
        store.pincode,
        'Current GPS location',
        lat: position.latitude,
        lng: position.longitude,
      );
      if (mounted) setState(() => locating = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          locationError = '$e'.replaceFirst('Bad state: ', '');
          locating = false;
        });
      }
    }
  }

  Future<void> _searchPlace() async {
    final place = await showModalBottomSheet<NominatimPlace>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PlaceSearchSheet(),
    );
    if (place == null) return;
    await store.setLocation('', place.displayName, lat: place.latitude, lng: place.longitude);
    if (mounted) setState(() => locationError = null);
  }

  Future<void> _dropPin() async {
    final initial = store.latitude != null && store.longitude != null
        ? LatLng(store.latitude!, store.longitude!)
        : null;
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => MapPinPickerPage(initialCenter: initial)),
    );
    if (point == null) return;
    await store.setLocation('', 'Pinned location', lat: point.latitude, lng: point.longitude);
    if (mounted) setState(() => locationError = null);
  }

  List<_Match> _matches(double radiusKm) {
    if (store.latitude == null || store.longitude == null) return const [];
    final matches = <_Match>[];
    for (final shop in store.visible('shops')) {
      final distance = distanceKm(
        store.latitude!,
        store.longitude!,
        shop.number('latitude'),
        shop.number('longitude'),
      );
      if (distance > radiusKm) continue;
      for (final product in store.visible('products').where((p) => p.text('shopId') == shop.id)) {
        matches.add(_Match(shop, product, distance));
      }
    }
    matches.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return matches;
  }

  void _openShopSheet(Entry shop, List<_Match> shopMatches) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(shop.text('name'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final match in shopMatches)
              ListTile(
                title: Text(match.product.text('name')),
                subtitle: Text('${money(match.product.price(store.pincode))} • ${match.distanceKm.toStringAsFixed(1)} km'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => ProductPage(store: store, entry: match.product)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radiusKm = presets[presetIndex];
    final hasLocation = store.latitude != null && store.longitude != null;
    final matches = hasLocation ? _matches(radiusKm) : const <_Match>[];
    final shopsById = <String, List<_Match>>{};
    for (final match in matches) {
      shopsById.putIfAbsent(match.shop.id, () => []).add(match);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Search products near me')),
      body: !hasLocation
          ? _locationPrompt(context)
          : ListenableBuilder(
              listenable: store,
              builder: (context, _) => ListView(
                // Lets tests jump straight to the results, avoiding drag
                // gestures that can be captured by the Slider above instead
                // of scrolling the list.
                key: const Key('product-search-results'),
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18, color: Color(0xff176b50)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          store.address.isEmpty ? 'Your location is set' : store.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(onPressed: () => setState(() => locationError = 'change'), child: const Text('Change')),
                    ],
                  ),
                  if (locationError == 'change') _changeLocationRow(),
                  const SizedBox(height: 8),
                  Text('Search radius: ${radiusKm.round()} km'),
                  Slider(
                    value: presetIndex.toDouble(),
                    min: 0,
                    max: (presets.length - 1).toDouble(),
                    divisions: presets.length > 1 ? presets.length - 1 : null,
                    label: '${radiusKm.round()} km',
                    onChanged: presets.length > 1
                        ? (value) => setState(() => presetIndex = value.round())
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No products found in this radius yet. Try a larger radius.'),
                    )
                  else ...[
                    ShopMap(
                      shops: shopsById.keys.map((id) => shopsById[id]!.first.shop).toList(),
                      latitude: store.latitude,
                      longitude: store.longitude,
                      radiusKm: radiusKm,
                      myLocationIcon: Icons.person_pin_circle,
                      onShop: (shop) => _openShopSheet(shop, shopsById[shop.id] ?? const []),
                    ),
                    const SizedBox(height: 16),
                    for (final match in matches) _ProductLocationTile(store: store, match: match),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _changeLocationRow() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(onPressed: _useGps, icon: const Icon(Icons.my_location), label: const Text('Use GPS')),
        OutlinedButton.icon(onPressed: _searchPlace, icon: const Icon(Icons.search), label: const Text('Search place')),
        OutlinedButton.icon(onPressed: _dropPin, icon: const Icon(Icons.pin_drop_outlined), label: const Text('Drop pin')),
      ],
    ),
  );

  Widget _locationPrompt(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_searching, size: 48, color: Color(0xff176b50)),
          const SizedBox(height: 16),
          if (locating) const CircularProgressIndicator(),
          if (!locating && locationError != null) ...[
            Text(locationError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
          ],
          if (!locating) ...[
            const Text('We need your location to search nearby products.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            _changeLocationRow(),
          ],
        ],
      ),
    ),
  );
}

class _ProductLocationTile extends StatelessWidget {
  const _ProductLocationTile({required this.store, required this.match});
  final Store store;
  final _Match match;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      leading: match.shop.text('imageUrl').isEmpty
          ? const CircleAvatar(child: Icon(Icons.storefront_outlined))
          : CircleAvatar(
              backgroundImage: NetworkImage(match.shop.text('imageUrl')),
              onBackgroundImageError: (_, _) {},
            ),
      title: Text(match.product.text('name')),
      subtitle: Text(
        '${money(match.product.price(store.pincode))} • ${match.distanceKm.toStringAsFixed(1)} km • ${match.shop.text('name')}\n${match.shop.text('address')}',
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: 'Directions',
        icon: const Icon(Icons.directions),
        onPressed: () async {
          final uri = Uri.https('www.google.com', '/maps/dir/', {
            'api': '1',
            'destination': '${match.shop.number('latitude')},${match.shop.number('longitude')}',
            if (store.latitude != null) 'origin': '${store.latitude},${store.longitude}',
          });
          try {
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
              message(context, 'Could not open directions');
            }
          } catch (e) {
            if (context.mounted) message(context, 'Could not open directions');
          }
        },
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => ProductPage(store: store, entry: match.product)),
      ),
    ),
  );
}
