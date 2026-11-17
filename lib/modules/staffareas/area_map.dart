import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'staff_area_model.dart';

const areaFreeColour = Color(0xFF16A34A);
const areaPendingColour = Color(0xFFF59E0B);
const areaBookedColour = Color(0xFFDC2626);

Color areaColour(String status) => switch (status) { 'free' => areaFreeColour, 'pending' => areaPendingColour, _ => areaBookedColour };
String areaStatusLabel(String status) => switch (status) { 'free' => 'Free', 'pending' => 'Pending', _ => 'Booked' };

/// A map of areas: each a circle (green free, orange pending, red booked), the chosen one drawn thicker, with optional shop pins
/// (a tick on those with an offer today), the staff member's own place, and a tap that chooses an area or puts a point.
class AreaMap extends StatelessWidget {
  const AreaMap({
    super.key,
    required this.areas,
    this.selectedId,
    this.shops = const [],
    this.me,
    this.point,
    this.onTapArea,
    this.onTapMap,
    this.height = 300,
  });
  final List<StaffArea> areas;
  final String? selectedId;
  final List<AreaShop> shops;
  final LatLng? me, point;
  final ValueChanged<StaffArea>? onTapArea;
  final ValueChanged<LatLng>? onTapMap;
  final double height;

  LatLng get _centre {
    final chosen = areas.where((a) => a.id == selectedId).firstOrNull;
    if (chosen != null) return LatLng(chosen.latitude, chosen.longitude);
    if (point != null) return point!;
    if (areas.isNotEmpty) return LatLng(areas.first.latitude, areas.first.longitude);
    return me ?? const LatLng(17.668, 82.612);
  }

  void _tap(LatLng at) {
    if (onTapArea != null) {
      const d = Distance();
      for (final a in areas) {
        if (d.as(LengthUnit.Meter, at, LatLng(a.latitude, a.longitude)) <= a.radiusKm * 1000) return onTapArea!(a);
      }
    }
    onTapMap?.call(at);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FlutterMap(
        options: MapOptions(initialCenter: _centre, initialZoom: 13.5, onTap: (_, at) => _tap(at)),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.neighbourly.ecommerce'),
          // A hexagon cell is drawn as its outline (owner, 13 Nov 2026); an older area as its circle.
          PolygonLayer(polygons: [
            for (final a in areas)
              if (a.hex)
                Polygon(points: a.outline, color: areaColour(a.status).withValues(alpha: 0.18), borderColor: areaColour(a.status), borderStrokeWidth: a.id == selectedId ? 4 : 2),
          ]),
          CircleLayer(circles: [
            for (final a in areas)
              if (!a.hex)
              CircleMarker(
                point: LatLng(a.latitude, a.longitude),
                radius: a.radiusKm * 1000,
                useRadiusInMeter: true,
                color: areaColour(a.status).withValues(alpha: 0.18),
                borderColor: areaColour(a.status),
                borderStrokeWidth: a.id == selectedId ? 4 : 2,
              ),
          ]),
          MarkerLayer(markers: [
            for (final a in areas)
              Marker(
                point: LatLng(a.latitude, a.longitude),
                width: 140,
                height: 34,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4)),
                      child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: areaColour(a.status))),
                    ),
                  ),
                ),
              ),
            for (final s in shops)
              Marker(
                point: LatLng(s.latitude, s.longitude),
                width: 30,
                height: 30,
                child: Icon(s.offerToday ? Icons.check_circle : Icons.storefront, color: s.offerToday ? areaFreeColour : const Color(0xFF6B7280), size: 24, semanticLabel: s.name),
              ),
            if (point != null) Marker(point: point!, width: 32, height: 32, child: const Icon(Icons.add_location_alt, color: Color(0xFF2563EB), size: 30)),
            if (me != null) Marker(point: me!, width: 26, height: 26, child: const Icon(Icons.person_pin_circle, color: Color(0xFF2563EB), size: 26)),
          ]),
        ],
      ),
    ),
  );
}

/// The legend under a map: Free, Pending, Booked.
class AreaLegend extends StatelessWidget {
  const AreaLegend({super.key});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 12, children: [
    for (final s in const ['free', 'pending', 'booked'])
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: areaColour(s), shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(areaStatusLabel(s)),
      ]),
  ]);
}
