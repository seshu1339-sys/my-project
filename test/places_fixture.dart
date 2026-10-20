import 'dart:convert';
import 'dart:io';

import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/services/places_directory.dart';

/// The real, shipped places file (web/data/places.v1.json), read from disk.
final String placesFileText = File(
  'web/data/${PlacesDirectory.fileName}',
).readAsStringSync();

/// The shipped file, parsed once and searchable.
final PlacesIndex realIndex = PlacesIndex.fromJson(
  jsonDecode(placesFileText) as Map<String, dynamic>,
);

/// Points [PlacesDirectory] at the shipped file instead of the network (and
/// off the real disk cache). Returns a counter of how many times the app asked
/// to download it. Call from `setUp`.
({int Function() fetches}) usePlacesFixture() {
  var fetches = 0;
  PlacesDirectory.instance
    ..reset()
    ..useDiskCache = false
    ..fetchText = () async {
      fetches++;
      return placesFileText;
    };
  return (fetches: () => fetches);
}
