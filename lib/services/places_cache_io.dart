import 'dart:io';

/// Phones/desktop: the downloaded places file is kept in the app's cache
/// folder, so after the first download the directory opens without network.
/// The file name carries the format version, so a new version never reads an
/// old copy.
File _file(String fileName) =>
    File('${Directory.systemTemp.path}${Platform.pathSeparator}$fileName');

Future<String?> readCachedPlaces(String fileName) async {
  try {
    final file = _file(fileName);
    if (await file.exists() && await file.length() > 0) {
      return await file.readAsString();
    }
  } catch (_) {}
  return null;
}

Future<void> writeCachedPlaces(String fileName, String body) async {
  try {
    await _file(fileName).writeAsString(body, flush: true);
  } catch (_) {
    // A cache that can't be written only costs a re-download next time.
  }
}
