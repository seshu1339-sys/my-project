import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/geocoding.dart';

/// A search-as-you-type bottom sheet for picking a place by name, backed by
/// the free OpenStreetMap Nominatim API. Pops with the selected
/// [NominatimPlace], or null if dismissed without a choice.
class PlaceSearchSheet extends StatefulWidget {
  const PlaceSearchSheet({super.key, this.geocoder});
  // Injectable for tests; a real instance is created lazily otherwise.
  final NominatimGeocoder? geocoder;
  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  late final NominatimGeocoder geocoder = widget.geocoder ?? NominatimGeocoder();
  final query = TextEditingController();
  Timer? debounce;
  List<NominatimPlace> results = const [];
  bool loading = false;
  String? error;

  void onChanged(String value) {
    debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        results = const [];
        error = null;
        loading = false;
      });
      return;
    }
    debounce = Timer(const Duration(milliseconds: 500), () => search(value));
  }

  Future<void> search(String value) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final found = await geocoder.search(value);
      if (mounted) {
        setState(() {
          results = found;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Search for a place', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: query,
              autofocus: true,
              onChanged: onChanged,
              decoration: const InputDecoration(
                labelText: 'Area, locality or landmark',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final place = results[i];
                  return ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(place.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, place),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A full-screen map for dropping a pin at any point. Pops with the chosen
/// [LatLng], or null if dismissed without confirming.
class MapPinPickerPage extends StatefulWidget {
  const MapPinPickerPage({super.key, this.initialCenter});
  final LatLng? initialCenter;
  @override
  State<MapPinPickerPage> createState() => _MapPinPickerPageState();
}

class _MapPinPickerPageState extends State<MapPinPickerPage> {
  late LatLng center = widget.initialCenter ?? const LatLng(20.5937, 78.9629);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Drop a pin on the map')),
    body: Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: widget.initialCenter != null ? 15 : 5,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) setState(() => center = camera.center);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.neighbourly.ecommerce',
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
                  ),
                ],
              ),
            ],
          ),
        ),
        // The map itself always stays centered under this fixed crosshair;
        // moving the map moves the pin, not the other way round. Shifted up
        // by half its height so the pin's visual tip (not its center) marks
        // the actual chosen point.
        IgnorePointer(
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: const Icon(Icons.location_on, size: 48, color: Color(0xff176b50)),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, center),
              icon: const Icon(Icons.check),
              label: const Text('Confirm this location'),
            ),
          ),
        ),
      ],
    ),
  );
}
