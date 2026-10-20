import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/places.dart';
import 'places_cache_stub.dart'
    if (dart.library.io) 'places_cache_io.dart';

/// The Andhra Pradesh / Telangana places directory (every post office, its
/// district and pincode), loaded ON DEMAND.
///
/// It is a static file served with Firebase Hosting (web/data/), built by
/// scripts/build-places.cjs. Nothing here runs at start-up: the home page
/// never touches it. It is fetched the first time a customer opens the
/// location dialog or an admin uses the Location search, then stays cached --
/// by the browser (one-year cache header) and the service worker on the web,
/// in the app's cache folder on a phone -- and in memory for the session.
class PlacesDirectory {
  PlacesDirectory._();
  static final PlacesDirectory instance = PlacesDirectory._();

  /// Bump with the generator's format version; the old file stays cached
  /// harmlessly under its own name.
  static const fileName = 'places.v1.json';

  /// Where phones/desktop download it from (the web build uses its own origin).
  static const nativeBaseUrl = String.fromEnvironment(
    'PLACES_BASE_URL',
    defaultValue: 'https://e-commerce-app-a3897.web.app',
  );

  /// Replaced in tests; returns the file's text.
  @visibleForTesting
  Future<String> Function() fetchText = _download;

  /// Tests turn this off so a fixture never lands in (or is read from) the
  /// real on-disk cache.
  @visibleForTesting
  bool useDiskCache = true;

  Future<PlacesIndex>? _loading;
  PlacesIndex? _ready;

  /// Null until [load] has finished -- lets a screen search instantly when
  /// the directory is already in memory.
  PlacesIndex? get ready => _ready;

  Future<PlacesIndex> load() => _loading ??= _load();

  Future<PlacesIndex> _load() async {
    try {
      final cached = useDiskCache ? await readCachedPlaces(fileName) : null;
      if (cached != null) {
        try {
          return _ready = _parse(cached);
        } catch (_) {
          // A damaged cache file: fall through and download a fresh copy.
        }
      }
      final text = await fetchText();
      final index = _parse(text);
      if (useDiskCache) await writeCachedPlaces(fileName, text);
      return _ready = index;
    } catch (_) {
      _loading = null; // let the next attempt retry
      rethrow;
    }
  }

  PlacesIndex _parse(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> || json['v'] != 1) {
      throw const FormatException('Unexpected places file');
    }
    return PlacesIndex.fromJson(json);
  }

  static Future<String> _download() async {
    final uri = kIsWeb
        ? Uri.parse('${Uri.base.origin}/data/$fileName')
        : Uri.parse('$nativeBaseUrl/data/$fileName');
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('The places list could not be downloaded.');
    }
    return utf8.decode(response.bodyBytes);
  }

  @visibleForTesting
  void reset() {
    _loading = null;
    _ready = null;
  }
}
