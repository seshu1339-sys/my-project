import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import 'area_map.dart';

/// Whether this build shows Google's map: an Android build made with --dart-define=GOOGLE_MAPS=true and a Maps key in
/// android/local.properties (MAPS_API_KEY). Otherwise the free OpenStreetMap map, so the app works without a key.
const useGoogleMaps = bool.fromEnvironment('GOOGLE_MAPS') && !kIsWeb;

/// The map where a staff member taps the centre of their area: the normal map (no Street View), the tapped centre and, once the server
/// answered, the area's circle. The map is made ONCE when the page opens and only its camera moves after that (to a searched place),
/// so it never loads again: this keeps Google's map requests near zero.
class AreaPickerMap extends StatefulWidget {
  const AreaPickerMap({super.key, required this.start, required this.onTap, this.centre, this.radiusKm, this.free = true, this.focus, this.height = 320});
  final LatLng start;
  final ValueChanged<LatLng> onTap;
  final LatLng? centre;
  final double? radiusKm;
  final bool free;
  // A searched place: the camera moves there (no new map).
  final LatLng? focus;
  final double height;

  @override
  State<AreaPickerMap> createState() => _AreaPickerMapState();
}

class _AreaPickerMapState extends State<AreaPickerMap> {
  gm.GoogleMapController? google;
  final osmController = osm.MapController();

  @override
  void didUpdateWidget(AreaPickerMap old) {
    super.didUpdateWidget(old);
    final f = widget.focus;
    if (f != null && f != old.focus) {
      if (useGoogleMaps) {
        google?.moveCamera(gm.CameraUpdate.newLatLngZoom(gm.LatLng(f.latitude, f.longitude), 14));
      } else {
        osmController.move(f, 14);
      }
    }
  }

  @override
  void dispose() {
    google?.dispose();
    super.dispose();
  }

  Color get _colour => widget.free ? areaFreeColour : areaBookedColour;

  Widget _google() {
    final c = widget.centre;
    return gm.GoogleMap(
      key: const ValueKey('area-picker-google'),
      initialCameraPosition: gm.CameraPosition(target: gm.LatLng(widget.start.latitude, widget.start.longitude), zoom: 13),
      mapType: gm.MapType.normal,
      // No Street View, no extra buttons: only the map, the tap and the circle.
      mapToolbarEnabled: false,
      buildingsEnabled: false,
      indoorViewEnabled: false,
      trafficEnabled: false,
      onMapCreated: (controller) => google = controller,
      onTap: (at) => widget.onTap(LatLng(at.latitude, at.longitude)),
      markers: {if (c != null) gm.Marker(markerId: const gm.MarkerId('centre'), position: gm.LatLng(c.latitude, c.longitude))},
      circles: {
        if (c != null && widget.radiusKm != null)
          gm.Circle(
            circleId: const gm.CircleId('area'),
            center: gm.LatLng(c.latitude, c.longitude),
            radius: widget.radiusKm! * 1000,
            strokeColor: _colour,
            strokeWidth: 3,
            fillColor: _colour.withValues(alpha: 0.15),
          ),
      },
    );
  }

  Widget _osm() {
    final c = widget.centre;
    return osm.FlutterMap(
      key: const ValueKey('area-picker-osm'),
      mapController: osmController,
      options: osm.MapOptions(initialCenter: widget.start, initialZoom: 13, onTap: (_, at) => widget.onTap(at)),
      children: [
        osm.TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'in.locamarket.staff'),
        if (c != null && widget.radiusKm != null)
          osm.CircleLayer(circles: [
            osm.CircleMarker(point: c, radius: widget.radiusKm! * 1000, useRadiusInMeter: true, color: _colour.withValues(alpha: 0.15), borderColor: _colour, borderStrokeWidth: 3),
          ]),
        if (c != null) osm.MarkerLayer(markers: [osm.Marker(point: c, width: 36, height: 36, child: Icon(Icons.location_pin, color: _colour, size: 36))]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: useGoogleMaps ? _google() : _osm()),
  );
}
