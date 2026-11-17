import 'dart:convert';

import 'package:http/http.dart' as http;

/// Automatic staff areas (owner, 7 Nov 2026): the staff member searches a place, taps the centre on the map, and the server counts the
/// buildings around it in free OpenStreetMap data and sets the radius (functions/modules/staff-areas/blocks.js). Staff never set it.

/// What the server says about a tapped centre (previewAutoStaffArea).
class AutoAreaPreview {
  const AutoAreaPreview({
    required this.blockId,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.buildings,
    required this.densityPerKm2,
    required this.free,
    this.problem = '',
  });

  factory AutoAreaPreview.fromData(Map<String, dynamic> d) => AutoAreaPreview(
    blockId: '${d['blockId'] ?? ''}',
    latitude: (d['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (d['longitude'] as num?)?.toDouble() ?? 0,
    radiusKm: (d['radiusKm'] as num?)?.toDouble() ?? 0,
    buildings: (d['buildings'] as num?)?.toInt() ?? 0,
    densityPerKm2: (d['densityPerKm2'] as num?)?.toInt() ?? 0,
    free: d['free'] == true,
    problem: '${d['problem'] ?? ''}',
  );

  final String blockId, problem;
  final double latitude, longitude, radiusKm;
  final int buildings, densityPerKm2;
  final bool free;

  String get radiusText => '${radiusKm == radiusKm.roundToDouble() ? radiusKm.toInt() : radiusKm} km';
}

/// A place found by the search: its name, its town and where it is.
class FoundPlace {
  const FoundPlace({required this.name, required this.town, required this.latitude, required this.longitude, this.detail = ''});
  final String name, town, detail;
  final double latitude, longitude;
}

/// Searches a place name in India with OpenStreetMap's free search (Nominatim), not Google, so the search costs nothing. One search
/// per tap of the Search button (the service allows about one a second).
Future<List<FoundPlace>> searchPlaces(String query, {http.Client? client}) async {
  final q = query.trim();
  if (q.length < 2) return const [];
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {'q': q, 'format': 'jsonv2', 'countrycodes': 'in', 'addressdetails': '1', 'limit': '6'});
  final response = await (client ?? http.Client()).get(uri, headers: {'User-Agent': 'LOCAMARKET-staff-app/1.0', 'Accept-Language': 'en'});
  if (response.statusCode != 200) throw 'The place search is busy. Try again in a minute.';
  final list = jsonDecode(response.body);
  if (list is! List) return const [];
  return [
    for (final p in list.whereType<Map>())
      if (double.tryParse('${p['lat']}') case final lat?)
        if (double.tryParse('${p['lon']}') case final lng?)
          FoundPlace(
            name: '${p['name'] ?? ''}'.isNotEmpty ? '${p['name']}' : '${p['display_name'] ?? q}'.split(',').first,
            town: _town(p['address']),
            detail: '${p['display_name'] ?? ''}',
            latitude: lat,
            longitude: lng,
          ),
  ];
}

String _town(Object? address) {
  if (address is! Map) return '';
  for (final key in ['city', 'town', 'village', 'suburb', 'county', 'state_district']) {
    final v = '${address[key] ?? ''}'.trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

/// The block of a tap, the same calculation as the server's (blocks.js): about 1.1 km squares over India. Used only to draw the
/// snapped centre at once; the server decides.
({String blockId, double latitude, double longitude}) blockOf(double lat, double lng) {
  const deg = 0.01;
  final row = (lat / deg).floor(), col = (lng / deg).floor();
  double round(double v) => (v * 1e6).roundToDouble() / 1e6;
  return (blockId: 'B${row}_$col', latitude: round((row + 0.5) * deg), longitude: round((col + 0.5) * deg));
}
