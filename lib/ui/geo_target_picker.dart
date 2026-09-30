import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/catalog.dart';

/// What [GeoTargetPicker] hands back: exactly one shape's worth of data, in
/// the same field names `promotionMatchesLocation` and `EntryEditor` expect.
class GeoTargetResult {
  const GeoTargetResult.circle({
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
  }) : shape = 'circle',
       rectangle = null,
       polygon = null;
  const GeoTargetResult.rectangle(Map<String, double> this.rectangle)
    : shape = 'rectangle',
      latitude = 0,
      longitude = 0,
      radiusKm = 0,
      polygon = null;
  const GeoTargetResult.polygon(List<Map<String, double>> this.polygon)
    : shape = 'polygon',
      latitude = 0,
      longitude = 0,
      radiusKm = 0,
      rectangle = null;

  final String shape;
  final double latitude, longitude, radiusKm;
  final Map<String, double>? rectangle;
  final List<Map<String, double>>? polygon;
}

bool _hasShapeTarget(Entry p) {
  final shape = p.text('geoShape', 'circle');
  if (shape == 'rectangle') return parseRectangleField(p.data['targetRectangle']) != null;
  if (shape == 'polygon') return parsePolygonField(p.data['targetPolygon']) != null;
  return p.number('targetLatitude') != 0 || p.number('targetLongitude') != 0;
}

// Open-ended (null) start/end are treated as "always", matching the
// documented judgment call: a promotion with no end date can still conflict
// with one that has none either.
bool _windowsOverlap(DateTime? aStart, DateTime? aEnd, DateTime? bStart, DateTime? bEnd) {
  if (aEnd != null && bStart != null && !aEnd.isAfter(bStart)) return false;
  if (bEnd != null && aStart != null && !bEnd.isAfter(aStart)) return false;
  return true;
}

Map<String, double> _rectangleFromCorners(LatLng a, LatLng b) => {
  'north': a.latitude > b.latitude ? a.latitude : b.latitude,
  'south': a.latitude < b.latitude ? a.latitude : b.latitude,
  'east': a.longitude > b.longitude ? a.longitude : b.longitude,
  'west': a.longitude < b.longitude ? a.longitude : b.longitude,
};

/// A full-screen map for drawing a promotion's target area as a Circle,
/// Rectangle or Polygon. Every other currently-bookable promotion (active,
/// shape-targeted, and whose display window overlaps the promotion being
/// edited) is shown in red, from data the caller already has loaded — no new
/// Firestore query. Drawing a shape that overlaps any red area requires an
/// explicit override checkbox before "Use this area" enables; with no
/// overlap it enables immediately. Pops with a [GeoTargetResult], or null if
/// dismissed without choosing.
class GeoTargetPicker extends StatefulWidget {
  const GeoTargetPicker({
    super.key,
    required this.promotions,
    this.excludeId,
    this.windowStart,
    this.windowEnd,
    this.initialShape = 'circle',
    this.initialLatitude = 0,
    this.initialLongitude = 0,
    this.initialRadiusKm = 0,
    this.initialRectangle,
    this.initialPolygon,
  });
  // All promotions the admin can already see (store.entries('promotions')) —
  // the source for the red "booked area" overlay.
  final List<Entry> promotions;
  // The promotion currently being edited, excluded from its own overlap
  // check; null when creating a brand-new promotion.
  final String? excludeId;
  final DateTime? windowStart, windowEnd;
  final String initialShape;
  final double initialLatitude, initialLongitude, initialRadiusKm;
  final Map<String, double>? initialRectangle;
  final GeoRing? initialPolygon;
  @override
  State<GeoTargetPicker> createState() => _GeoTargetPickerState();
}

class _GeoTargetPickerState extends State<GeoTargetPicker> {
  late String shape = widget.initialShape;
  LatLng? circleCenter;
  double circleRadiusKm = 5;
  LatLng? corner1, corner2;
  List<LatLng> points = [];
  bool overrideConfirmed = false;

  late final List<Entry> bookedCandidates = widget.promotions.where((p) {
    if (p.id == widget.excludeId) return false;
    if (!p.active) return false;
    if (!_hasShapeTarget(p)) return false;
    return _windowsOverlap(
      widget.windowStart,
      widget.windowEnd,
      DateTime.tryParse(p.text('startsAt')),
      DateTime.tryParse(p.text('endsAt')),
    );
  }).toList();

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != 0 || widget.initialLongitude != 0) {
      circleCenter = LatLng(widget.initialLatitude, widget.initialLongitude);
    }
    if (widget.initialRadiusKm > 0) circleRadiusKm = widget.initialRadiusKm;
    if (widget.initialRectangle != null) {
      corner1 = LatLng(widget.initialRectangle!['north']!, widget.initialRectangle!['west']!);
      corner2 = LatLng(widget.initialRectangle!['south']!, widget.initialRectangle!['east']!);
    }
    if (widget.initialPolygon != null) {
      points = widget.initialPolygon!.map((p) => LatLng(p.$1, p.$2)).toList();
    }
  }

  Entry? _draftEntry() {
    switch (shape) {
      case 'rectangle':
        if (corner1 == null || corner2 == null) return null;
        return Entry('__draft__', {
          'geoShape': 'rectangle',
          'targetRectangle': _rectangleFromCorners(corner1!, corner2!),
        });
      case 'polygon':
        if (points.length < 3) return null;
        return Entry('__draft__', {
          'geoShape': 'polygon',
          'targetPolygon': [for (final p in points) {'lat': p.latitude, 'lng': p.longitude}],
        });
      default:
        if (circleCenter == null) return null;
        return Entry('__draft__', {
          'geoShape': 'circle',
          'targetLatitude': circleCenter!.latitude,
          'targetLongitude': circleCenter!.longitude,
          'targetRadiusKm': circleRadiusKm,
        });
    }
  }

  bool get shapeComplete => _draftEntry() != null;

  List<Entry> get overlapping {
    final draft = _draftEntry();
    if (draft == null) return const [];
    return bookedCandidates.where((o) => promotionShapesOverlap(draft, o)).toList();
  }

  Color get draftColor => overlapping.isEmpty ? const Color(0xff176b50) : const Color(0xffff8f00);

  LatLng get initialCenter =>
      circleCenter ?? corner1 ?? (points.isNotEmpty ? points.first : null) ?? const LatLng(20.5937, 78.9629);

  void onMapTap(LatLng point) => setState(() {
    switch (shape) {
      case 'circle':
        circleCenter = point;
      case 'rectangle':
        if (corner1 == null) {
          corner1 = point;
        } else if (corner2 == null) {
          corner2 = point;
        } else {
          corner1 = point;
          corner2 = null;
        }
      case 'polygon':
        points.add(point);
    }
    overrideConfirmed = false;
  });

  void confirm() {
    switch (shape) {
      case 'rectangle':
        if (corner1 == null || corner2 == null) return;
        Navigator.pop(context, GeoTargetResult.rectangle(_rectangleFromCorners(corner1!, corner2!)));
      case 'polygon':
        if (points.length < 3) return;
        Navigator.pop(
          context,
          GeoTargetResult.polygon([for (final p in points) {'lat': p.latitude, 'lng': p.longitude}]),
        );
      default:
        if (circleCenter == null) return;
        Navigator.pop(
          context,
          GeoTargetResult.circle(
            latitude: circleCenter!.latitude,
            longitude: circleCenter!.longitude,
            radiusKm: circleRadiusKm,
          ),
        );
    }
  }

  List<CircleMarker> get bookedCircles => [
    for (final p in bookedCandidates.where((p) => p.text('geoShape', 'circle') == 'circle'))
      CircleMarker(
        point: LatLng(p.number('targetLatitude'), p.number('targetLongitude')),
        radius: (p.number('targetRadiusKm') > 0 ? p.number('targetRadiusKm') : 10) * 1000,
        useRadiusInMeter: true,
        color: const Color(0xffcc0000).withValues(alpha: .2),
        borderColor: const Color(0xffcc0000),
        borderStrokeWidth: 2,
      ),
  ];

  List<Polygon> get bookedPolygons => [
    for (final p in bookedCandidates.where((p) => p.text('geoShape', 'circle') != 'circle'))
      Polygon(
        points: [
          for (final pt
              in p.text('geoShape') == 'rectangle'
                  ? rectangleRing(parseRectangleField(p.data['targetRectangle'])!)
                  : parsePolygonField(p.data['targetPolygon'])!)
            LatLng(pt.$1, pt.$2),
        ],
        color: const Color(0xffcc0000).withValues(alpha: .2),
        borderColor: const Color(0xffcc0000),
        borderStrokeWidth: 2,
      ),
  ];

  List<Widget> get draftLayers {
    final color = draftColor;
    switch (shape) {
      case 'circle':
        if (circleCenter == null) return const [];
        return [
          CircleLayer(
            circles: [
              CircleMarker(
                point: circleCenter!,
                radius: circleRadiusKm * 1000,
                useRadiusInMeter: true,
                color: color.withValues(alpha: .2),
                borderColor: color,
                borderStrokeWidth: 3,
              ),
            ],
          ),
          MarkerLayer(markers: [Marker(point: circleCenter!, child: Icon(Icons.my_location, color: color))]),
        ];
      case 'rectangle':
        if (corner1 == null) return const [];
        if (corner2 == null) {
          return [MarkerLayer(markers: [Marker(point: corner1!, child: Icon(Icons.place, color: color))])];
        }
        return [
          PolygonLayer(
            polygons: [
              Polygon(
                points: [for (final pt in rectangleRing(_rectangleFromCorners(corner1!, corner2!))) LatLng(pt.$1, pt.$2)],
                color: color.withValues(alpha: .2),
                borderColor: color,
                borderStrokeWidth: 3,
              ),
            ],
          ),
        ];
      default:
        return [
          if (points.length >= 2) PolylineLayer(polylines: [Polyline(points: points, color: color, strokeWidth: 3)]),
          if (points.length >= 3)
            PolygonLayer(
              polygons: [Polygon(points: points, color: color.withValues(alpha: .2), borderColor: color, borderStrokeWidth: 3)],
            ),
          MarkerLayer(
            markers: [for (final p in points) Marker(point: p, width: 16, height: 16, child: Icon(Icons.circle, size: 12, color: color))],
          ),
        ];
    }
  }

  Widget controlsFor(String shape) {
    switch (shape) {
      case 'circle':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(circleCenter == null ? 'Tap the map to place the center.' : 'Radius: ${circleRadiusKm.round()} km'),
            Slider(
              value: circleRadiusKm,
              min: 1,
              max: 100,
              divisions: 99,
              label: '${circleRadiusKm.round()} km',
              onChanged: circleCenter == null
                  ? null
                  : (v) => setState(() {
                      circleRadiusKm = v;
                      overrideConfirmed = false;
                    }),
            ),
          ],
        );
      case 'rectangle':
        return Row(
          children: [
            Expanded(
              child: Text(
                corner1 == null
                    ? 'Tap one corner, then the opposite corner.'
                    : corner2 == null
                    ? 'Now tap the opposite corner.'
                    : 'Rectangle set. Tap again to redraw.',
              ),
            ),
            if (corner1 != null)
              TextButton(
                onPressed: () => setState(() {
                  corner1 = null;
                  corner2 = null;
                  overrideConfirmed = false;
                }),
                child: const Text('Clear'),
              ),
          ],
        );
      default:
        return Row(
          children: [
            Expanded(
              child: Text(
                points.length < 3
                    ? 'Tap at least 3 points (${points.length} so far).'
                    : 'Polygon set (${points.length} points). Tap to add more.',
              ),
            ),
            if (points.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  points.removeLast();
                  overrideConfirmed = false;
                }),
                child: const Text('Undo point'),
              ),
            if (points.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  points.clear();
                  overrideConfirmed = false;
                }),
                child: const Text('Clear'),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = overlapping;
    final canConfirm = shapeComplete && (conflicts.isEmpty || overrideConfirmed);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose target area')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'circle', label: Text('Circle'), icon: Icon(Icons.circle_outlined)),
                ButtonSegment(value: 'rectangle', label: Text('Rectangle'), icon: Icon(Icons.crop_square)),
                ButtonSegment(value: 'polygon', label: Text('Polygon'), icon: Icon(Icons.pentagon_outlined)),
              ],
              selected: {shape},
              onSelectionChanged: (selection) => setState(() => shape = selection.first),
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: circleCenter != null || corner1 != null || points.isNotEmpty ? 13 : 5,
                onTap: (tapPosition, point) => onMapTap(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.neighbourly.ecommerce',
                ),
                if (bookedPolygons.isNotEmpty) PolygonLayer(polygons: bookedPolygons),
                if (bookedCircles.isNotEmpty) CircleLayer(circles: bookedCircles),
                ...draftLayers,
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
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: controlsFor(shape)),
          if (conflicts.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xffcc0000).withValues(alpha: .08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xffcc0000)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_outlined, color: Color(0xffcc0000)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This overlaps an active booking: ${conflicts.map((e) => e.text('name', e.id)).join(', ')}',
                          style: const TextStyle(color: Color(0xffcc0000)),
                        ),
                      ),
                    ],
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: overrideConfirmed,
                      onChanged: (v) => setState(() => overrideConfirmed = v ?? false),
                      title: const Text('Save anyway (override this overlap)'),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: canConfirm ? confirm : null,
              icon: const Icon(Icons.check),
              label: const Text('Use this area'),
            ),
          ),
        ],
      ),
    );
  }
}
