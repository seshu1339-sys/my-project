import 'dart:convert';
import 'dart:io';

import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/services/places_directory.dart';

/// The text of a shipped places file (web/data/<name>), read from disk.
String placesFileNamed(String fileName) => File('web/data/$fileName').readAsStringSync();

/// The shipped places index (every state and its districts).
final PlacesManifest realManifest = PlacesManifest.fromJson(
  jsonDecode(placesFileNamed(PlacesDirectory.indexFileName)) as Map<String, dynamic>,
);

/// The shipped files of the home states (Andhra Pradesh, Telangana), joined: the shape the app
/// reads, and most of the tests' "real directory".
final Map<String, dynamic> realIndexJson = mergePlaceFiles([
  for (final name in PlacesDirectory.homeStates)
    jsonDecode(placesFileNamed(realManifest.named(name)!.file)) as Map<String, dynamic>,
]);

/// The home states, parsed once and searchable.
final PlacesIndex realIndex = PlacesIndex.fromJson(realIndexJson);

/// Points [PlacesDirectory] at the shipped files instead of the network (and
/// off the real disk cache). Returns a counter of how many times the app asked
/// to download a state's file (the small index is not counted). Call from `setUp`.
({int Function() fetches}) usePlacesFixture() {
  var fetches = 0;
  PlacesDirectory.instance
    ..reset()
    ..useDiskCache = false
    ..fetchText = (fileName) async {
      if (fileName != PlacesDirectory.indexFileName) fetches++;
      return placesFileNamed(fileName);
    };
  return (fetches: () => fetches);
}
