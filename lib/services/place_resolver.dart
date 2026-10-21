import '../data/store.dart';
import 'places_directory.dart';

/// Fills in the customer's missing town / district / state from the places
/// directory (see [Store.completePlace]). Loads the directory (a one-time fetch,
/// then cached) and never throws: with no network the customer simply keeps
/// seeing the general offers until it can be done.
Future<void> completeStoredPlace(Store store) async {
  try {
    await store.completePlace(await PlacesDirectory.instance.load());
  } catch (_) {}
}

/// True when the customer's place is incomplete AND some offer or ad is aimed
/// at specific locations -- the only case where the directory is worth
/// loading outside the location dialog (so most visits never fetch it).
bool needsPlaceResolution(Store store) {
  if (store.pincode.isEmpty && store.town.isEmpty) return false;
  final complete = store.town.isNotEmpty && store.district.isNotEmpty;
  if (complete) return false;
  return store.entries('promotions').any((e) => e.text('locations').trim().isNotEmpty);
}
