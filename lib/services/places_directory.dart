import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/places.dart';
import 'places_cache_stub.dart'
    if (dart.library.io) 'places_cache_io.dart';

/// The places directory of India (every post office, its district and pincode), loaded ON DEMAND,
/// one state at a time.
///
/// It is static files served with Firebase Hosting (web/data/), built by scripts/build-places.cjs:
/// a small index of the states and their districts, and one file per state (Andhra Pradesh is about
/// 130 KB compressed). Nothing here runs at start-up: the home page never touches it. A state's
/// file is fetched the first time it is needed (the customer opens the location dialog, a GPS fix
/// lands in it, an admin searches), then stays cached -- by the browser (one-year cache header) on
/// the web, in the app's cache folder on a phone -- and in memory for the session.
class PlacesDirectory {
  PlacesDirectory._();
  static final PlacesDirectory instance = PlacesDirectory._();

  /// Bump with the generator's format version; the old files stay cached harmlessly under their
  /// own names.
  static const indexFileName = 'places.index.v1.json';

  /// The states [load] fetches when it is not told which: the two this app started with.
  static const homeStates = ['Andhra Pradesh', 'Telangana'];

  /// Where phones/desktop download it from (the web build uses its own origin).
  static const nativeBaseUrl = String.fromEnvironment(
    'PLACES_BASE_URL',
    defaultValue: 'https://e-commerce-app-a3897.web.app',
  );

  /// Replaced in tests; returns the text of the named file.
  @visibleForTesting
  Future<String> Function(String fileName) fetchText = _download;

  /// Tests turn this off so a fixture never lands in (or is read from) the
  /// real on-disk cache.
  @visibleForTesting
  bool useDiskCache = true;

  Future<PlacesManifest>? _manifestLoading;
  PlacesManifest? _manifest;
  final _states = <String, Map<String, dynamic>>{}; // state name -> its parsed file
  final _stateLoading = <String, Future<void>>{};
  PlacesIndex? _ready;

  /// The index of every state loaded so far; null until one has been -- lets a screen search
  /// instantly when the directory is already in memory.
  PlacesIndex? get ready => _ready;

  /// The states and their districts (loaded once; small).
  PlacesManifest? get manifestIfLoaded => _manifest;

  Future<PlacesManifest> manifest() => _manifestLoading ??= _loadManifest();

  Future<PlacesManifest> _loadManifest() async {
    try {
      final text = await _fileText(indexFileName);
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic> || json['v'] != 1) {
        throw const FormatException('Unexpected places index');
      }
      return _manifest = PlacesManifest.fromJson(json);
    } catch (_) {
      _manifestLoading = null; // let the next attempt retry
      rethrow;
    }
  }

  /// The directory of [states] (the home states when none are named), together with every
  /// state loaded before.
  Future<PlacesIndex> load({Iterable<String>? states}) async {
    final wanted = (states ?? homeStates).toList();
    final infos = await manifest();
    for (final name in wanted) {
      if (infos.named(name) == null) {
        throw StateError('Unknown state: $name');
      }
    }
    await Future.wait([for (final name in wanted) _loadState(infos.named(name)!)]);
    return _ready!;
  }

  /// The directory of the state(s) a GPS fix lies in -- the fix's own state(s) only, not the
  /// home states. Throws when it lies in none of them (outside India).
  Future<PlacesIndex> loadForPoint(double latitude, double longitude) async {
    final found = (await manifest()).statesAt(latitude, longitude);
    if (found.isEmpty) throw StateError('That place is not in India.');
    // Near a border a fix can lie in the boxes of a few states; they are small, so take them all.
    return load(states: [for (final s in found.take(4)) s.name]);
  }

  /// The directory of the state(s) a pincode can belong to.
  Future<PlacesIndex> loadForPincode(String pincode) async {
    final found = (await manifest()).statesForPincode(pincode.trim());
    if (found.isEmpty) throw StateError('Unknown pincode: $pincode');
    return load(states: [for (final s in found) s.name]);
  }

  /// Every state (the admin's search covers all of India: about 1.7 MB compressed).
  Future<PlacesIndex> loadAll() async {
    final infos = await manifest();
    return load(states: [for (final s in infos.states) s.name]);
  }

  Future<void> _loadState(PlaceStateInfo info) {
    if (_states.containsKey(info.name)) return Future.value();
    return _stateLoading[info.name] ??= () async {
      try {
        final json = jsonDecode(await _fileText(info.file));
        if (json is! Map<String, dynamic> || json['v'] != 1) {
          throw const FormatException('Unexpected places file');
        }
        _states[info.name] = json;
        _ready = PlacesIndex.fromJson(
          mergePlaceFiles([for (final file in _states.values) file]),
        );
      } finally {
        _stateLoading.remove(info.name); // a failure can be retried
      }
    }();
  }

  /// The file's text: from the app's cache when it is there (and readable), else downloaded.
  Future<String> _fileText(String fileName) async {
    final cached = useDiskCache ? await readCachedPlaces(fileName) : null;
    if (cached != null) {
      try {
        jsonDecode(cached);
        return cached;
      } catch (_) {
        // A damaged cache file: fall through and download a fresh copy.
      }
    }
    final text = await fetchText(fileName);
    if (useDiskCache) await writeCachedPlaces(fileName, text);
    return text;
  }

  static Future<String> _download(String fileName) async {
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
    _manifestLoading = null;
    _manifest = null;
    _states.clear();
    _stateLoading.clear();
    _ready = null;
  }
}
