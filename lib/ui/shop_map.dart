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
  });
  final List<Entry> shops;
  final double? latitude, longitude;
  final double height;
  final ValueChanged<Entry>? onShop;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(
            shops.first.number('latitude'),
            shops.first.number('longitude'),
          ),
          initialZoom: 12,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.neighbourly.ecommerce',
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
                  child: const Icon(Icons.my_location, color: Colors.blue),
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
