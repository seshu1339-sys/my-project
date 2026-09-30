import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/catalog.dart';

/// A small OpenStreetMap view with a pin per shop in [shops], and an optional
/// second "my location" pin at [latitude]/[longitude]. Shared by the customer
/// shop page and the admin panel (vendor application review, active vendors).
class ShopMap extends StatelessWidget {
  const ShopMap({
    super.key,
    required this.shops,
    this.latitude,
    this.longitude,
    this.height = 300,
    this.onShop,
    this.radiusKm,
    this.myLocationIcon = Icons.my_location,
  });
  final List<Entry> shops;
  final double? latitude, longitude;
  final double height;
  final ValueChanged<Entry>? onShop;
  // A radius circle drawn around latitude/longitude, in kilometers. Ignored
  // unless latitude/longitude are also set.
  final double? radiusKm;
  // Lets a caller show the "my location" pin as a person/avatar marker
  // instead of the default, without changing any other caller's rendering.
  final IconData myLocationIcon;
  @override
  Widget build(BuildContext context) {
    // An empty shops list with no "my location" point has nothing to center
    // on; shops.first below would otherwise throw. Fall back to the caller's
    // own location when known, else a fixed neutral default.
    final center = shops.isNotEmpty
        ? LatLng(
            shops.first.number('latitude'),
            shops.first.number('longitude'),
          )
        : (latitude != null && longitude != null)
        ? LatLng(latitude!, longitude!)
        : const LatLng(20.5937, 78.9629);
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 12),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.neighbourly.ecommerce',
            ),
            if (radiusKm != null && latitude != null && longitude != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(latitude!, longitude!),
                    radius: radiusKm! * 1000,
                    useRadiusInMeter: true,
                    color: const Color(0x22176b50),
                    borderColor: const Color(0xff176b50),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final shop in shops)
                  Marker(
                    point: LatLng(
                      shop.number('latitude'),
                      shop.number('longitude'),
                    ),
                    width: 50,
                    height: 50,
                    child: Tooltip(
                      message: shop.text('name'),
                      child: IconButton(
                        onPressed: onShop == null ? null : () => onShop!(shop),
                        icon: const Icon(
                          Icons.location_on,
                          size: 36,
                          color: Color(0xff176b50),
                        ),
                      ),
                    ),
                  ),
                if (latitude != null && longitude != null)
                  Marker(
                    point: LatLng(latitude!, longitude!),
                    child: Icon(myLocationIcon, color: Colors.blue),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () => launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
