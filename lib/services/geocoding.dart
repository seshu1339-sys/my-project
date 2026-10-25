import 'dart:convert';

import 'package:http/http.dart' as http;

/// A single OpenStreetMap Nominatim search result.
class NominatimPlace {
  const NominatimPlace({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
  final String displayName;
  final double latitude, longitude;
}

/// A street address worked out from a GPS point (reverse geocoding).
class ReverseAddress {
  const ReverseAddress({required this.text, this.pincode = '', this.town = ''});

  /// e.g. "Main Road, Krishna Bazar, Narsipatnam, 531116"
  final String text;

  /// The six-digit postcode, or '' when OpenStreetMap does not know it.
  final String pincode;
  final String town;
}

/// The readable address of a Nominatim reverse result: house number and road, the area, the town and the postcode (only the parts
/// that are there). Falls back to the full display name.
ReverseAddress? reverseAddressFromJson(Object? decoded) {
  if (decoded is! Map) return null;
  final address = decoded['address'];
  String part(List<String> keys) {
    if (address is! Map) return '';
    for (final key in keys) {
      final value = address[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  final postcode = part(const ['postcode']).replaceAll(' ', '');
  final pincode = RegExp(r'^\d{6}$').hasMatch(postcode) ? postcode : '';
  final town = part(const ['city', 'town', 'village', 'municipality']);
  final street = [part(const ['house_number']), part(const ['road', 'pedestrian', 'footway'])].where((p) => p.isNotEmpty).join(' ');
  final parts = <String>[];
  for (final p in [street, part(const ['neighbourhood', 'suburb', 'quarter', 'hamlet']), town, pincode]) {
    if (p.isNotEmpty && !parts.contains(p)) parts.add(p);
  }
  final display = decoded['display_name'];
  final text = parts.length >= 2 ? parts.join(', ') : (display is String ? display.trim() : parts.join(', '));
  if (text.isEmpty) return null;
  return ReverseAddress(text: text, pincode: pincode, town: town);
}

/// Free place-name search via OpenStreetMap's Nominatim API — no API key,
/// matching the app's existing OpenStreetMap/flutter_map tile stack instead
/// of a paid geocoding service. Client is injectable for tests.
///
/// Nominatim's usage policy requires a descriptive User-Agent identifying the
/// app and a way to contact its operator (see
/// https://operations.osmfoundation.org/policies/nominatim/).
class NominatimGeocoder {
  NominatimGeocoder({http.Client? client, String? contactEmail})
    : _client = client ?? http.Client(),
      _contactEmail = (contactEmail ?? '').trim().isEmpty
          ? placeholderContactEmail
          : contactEmail!.trim();
  final http.Client _client;
  final String _contactEmail;

  /// Dummy contact used until the owner sets the public support email in the
  /// admin panel (Business settings -> supportEmail), which callers pass in.
  static const placeholderContactEmail = 'support@example.com';
  String get _userAgent => 'Neighbourly/1.0 (contact: $_contactEmail)';

  /// The town/city name for a point, or '' when it cannot be worked out (offline,
  /// rate limited, open sea...). Never throws: a missing town only means the
  /// customer sees the general offers instead of a town's own.
  Future<String> reverseTown(double latitude, double longitude) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '$latitude',
        'lon': '$longitude',
        'zoom': '12',
        'addressdetails': '1',
      });
      final response = await _client.get(uri, headers: {'User-Agent': _userAgent});
      if (response.statusCode != 200) return '';
      final decoded = jsonDecode(response.body);
      final address = decoded is Map ? decoded['address'] : null;
      if (address is! Map) return '';
      for (final key in const ['city', 'town', 'village', 'municipality', 'suburb', 'county']) {
        final value = address[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    } catch (_) {}
    return '';
  }

  /// The street address at a point (for a vendor's shop or a provider's house), or null when it cannot be worked out. Never throws.
  Future<ReverseAddress?> reverseAddress(double latitude, double longitude) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '$latitude',
        'lon': '$longitude',
        'zoom': '18',
        'addressdetails': '1',
      });
      final response = await _client.get(uri, headers: {'User-Agent': _userAgent});
      if (response.statusCode != 200) return null;
      return reverseAddressFromJson(jsonDecode(response.body));
    } catch (_) {
      return null;
    }
  }

  Future<List<NominatimPlace>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'json',
      'q': trimmed,
      'limit': '8',
    });
    final response = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) {
      throw StateError('Could not search for that place. Please try again.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map &&
            item['display_name'] is String &&
            double.tryParse('${item['lat']}') != null &&
            double.tryParse('${item['lon']}') != null)
          NominatimPlace(
            displayName: item['display_name'] as String,
            latitude: double.parse('${item['lat']}'),
            longitude: double.parse('${item['lon']}'),
          ),
    ];
  }
}
