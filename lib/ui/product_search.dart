import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/geocoding.dart';
import '../services/location.dart';
import '../services/area_lookup.dart';
import '../services/usage.dart';
import 'location_picker_dialog.dart' show kmLabel;
import 'design_tokens.dart';
import 'product_page.dart';
import 'location_picker.dart';
import 'shared.dart';
import 'shop_map.dart';

import '../services/strings.dart';
import 'shop_ratings.dart';

/// A shop, joined with one of its products, at a known distance from the
/// customer — the unit both the map markers and the list rows are built from.
class _Match {
  const _Match(this.shop, this.product, this.distanceKm);
  final Entry shop, product;
  final double distanceKm;
}

/// Location-based product search: a map + list of the products of the shops within the admin's one km (Settings > Business Profile;
/// the same km as everything customers see), joined via each product's `shopId` to its shop's saved latitude/longitude.
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

  @override
  void initState() {
    super.initState();
    Usage.screen('nearby_search');
    if (!store.located) {
      _useGps();
    }
  }

  /// Saves [place] as the customer's place (the same as the place picker: area, shops and offers change everywhere).
  Future<void> _choose(Future<FoundPlace> Function() find, {bool gps = false}) async {
    setState(() {
      locating = true;
      locationError = null;
    });
    try {
      await savePlace(store, await find(), followGps: gps);
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

  Future<void> _useGps() => _choose(() async {
    final position = await currentPosition(action: 'search nearby products');
    if (!exactEnough(position)) {
      throw StateError('Your exact location could not be found. Search for your place or drop a pin instead.');
    }
    return placeAtPoint(store, position.latitude, position.longitude);
  }, gps: true);

  Future<void> _searchPlace() async {
    final place = await showModalBottomSheet<NominatimPlace>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PlaceSearchSheet(
        contactEmail: store.business.text('supportEmail'),
      ),
    );
    if (place == null) return;
    await _choose(() => placeAtPoint(store, place.latitude, place.longitude));
  }

  Future<void> _dropPin() async {
    final initial = store.located ? LatLng(store.latitude!, store.longitude!) : null;
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => MapPinPickerPage(initialCenter: initial)),
    );
    if (point == null) return;
    await _choose(() => placeAtPoint(store, point.latitude, point.longitude));
  }

  /// The products of the shops within the admin's km (the same km as everywhere: lib/domain/reach.dart), nearest shop first.
  List<_Match> _matches() {
    if (!store.located) return const [];
    final matches = <_Match>[];
    for (final shop in store.nearby()) {
      final distance = distanceKm(
        store.latitude!,
        store.longitude!,
        shop.number('latitude'),
        shop.number('longitude'),
      );
      for (final product in store.visibleProducts().where((p) => p.text('shopId') == shop.id)) {
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
            if (ratingLabel(shop).isNotEmpty) Text(ratingLabel(shop), key: const ValueKey('search-shop-rating')),
            for (final r in recentRatings(shop)) Text('${stars(r.stars)}  ${r.name}: ${r.comment}'),
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
    final radiusKm = store.reachKm;
    final hasLocation = store.located;
    final matches = hasLocation ? _matches() : const <_Match>[];
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
                      const Icon(Icons.location_on_outlined, size: 18, color: AppTokens.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          store.placeName.isEmpty ? 'Your location is set'.tr(context) : store.placeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(onPressed: () => setState(() => locationError = 'change'), child: Text('Change'.tr(context))),
                    ],
                  ),
                  if (locationError == 'change') _changeLocationRow(),
                  const SizedBox(height: 8),
                  Text('Shops within {km} km'.tr(context, {'km': kmLabel(radiusKm)})),
                  const SizedBox(height: 12),
                  if (matches.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No products near you yet.'.tr(context)),
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
        OutlinedButton.icon(onPressed: _useGps, icon: const Icon(Icons.my_location), label: Text('Use GPS'.tr(context))),
        OutlinedButton.icon(onPressed: _searchPlace, icon: const Icon(Icons.search), label: Text('Search place'.tr(context))),
        OutlinedButton.icon(onPressed: _dropPin, icon: const Icon(Icons.pin_drop_outlined), label: Text('Drop pin'.tr(context))),
      ],
    ),
  );

  Widget _locationPrompt(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_searching, size: 48, color: AppTokens.primary),
          const SizedBox(height: 16),
          if (locating) const CircularProgressIndicator(),
          if (!locating && locationError != null) ...[
            Text(locationError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
          ],
          if (!locating) ...[
            Text('We need your location to search nearby products.'.tr(context), textAlign: TextAlign.center),
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
        '${money(match.product.price(store.pincode))} • ${match.distanceKm.toStringAsFixed(1)} km • ${match.shop.text('name')}${ratingLabel(match.shop).isEmpty ? '' : ' ${ratingLabel(match.shop)}'}\n${match.shop.text('address')}',
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: 'Directions'.tr(context),
        icon: const Icon(Icons.directions),
        onPressed: () async {
          Usage.track('shop_directions', key: match.shop.id, label: match.shop.text('name'), town: match.shop.text('town'));
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
