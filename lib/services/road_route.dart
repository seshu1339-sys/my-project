import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// The road between two places for the map: its points, length and driving time.
class RoadRoute {
  const RoadRoute(this.points, {this.meters, this.seconds});
  final List<LatLng> points;
  final double? meters, seconds;
  bool get byRoad => meters != null;
}

final _cache = <String, RoadRoute>{};

/// The road from [from] to [to] (OSRM, the OpenStreetMap route service), kept for this visit. When the road cannot be found (no
/// network, the service is busy) the route is a straight line, so the map always shows the way.
Future<RoadRoute> roadRoute(LatLng from, LatLng to, {http.Client? client}) async {
  final key = [from.latitude, from.longitude, to.latitude, to.longitude].map((v) => v.toStringAsFixed(5)).join(',');
  final cached = _cache[key];
  if (cached != null) return cached;
  final url = Uri.https('router.project-osrm.org', '/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}', {
    'overview': 'full',
    'geometries': 'geojson',
  });
  try {
    final response = await (client ?? http.Client()).get(url).timeout(const Duration(seconds: 8));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final route = (body['routes'] as List?)?.firstOrNull as Map<String, dynamic>?;
    final coordinates = (route?['geometry'] as Map?)?['coordinates'] as List?;
    if (response.statusCode == 200 && body['code'] == 'Ok' && coordinates != null && coordinates.length >= 2) {
      return _cache[key] = RoadRoute(
        [for (final c in coordinates) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())],
        meters: (route!['distance'] as num?)?.toDouble(),
        seconds: (route['duration'] as num?)?.toDouble(),
      );
    }
  } catch (_) {
    /* the straight line below */
  }
  return RoadRoute([from, to]);
}

/// "1.2 km • 4 min by road" or "".
String roadRouteText(RoadRoute route) {
  final m = route.meters, s = route.seconds;
  if (m == null) return '';
  final distance = m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
  final minutes = s == null ? null : (s / 60).ceil();
  return minutes == null ? '$distance by road' : '$distance • $minutes min by road';
}
