/// Web: the browser's HTTP cache and the app's service worker keep the places
/// file (served with a one-year cache header), so there is nothing to store.
Future<String?> readCachedPlaces(String fileName) async => null;
Future<void> writeCachedPlaces(String fileName, String body) async {}
