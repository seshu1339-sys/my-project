import '../data/store.dart';
import 'area_lookup.dart';

/// A place saved before areas and distance-only offers existed (lib/domain/reach.dart): a pincode or a town without a point, or a
/// point without an area name. [completeStoredPlace] turns it into a full place once; the customer does not have to choose again.
bool needsPlaceResolution(Store store) {
  if (!store.located) return store.pincode.isNotEmpty || store.town.isNotEmpty;
  return store.area.isEmpty;
}

/// Completes the saved place (see [needsPlaceResolution]): the pincode's or the town's point, or the area at the saved point. Never
/// throws: when it cannot be done now (no connection) the customer keeps what they have and it is tried again on a later open.
Future<void> completeStoredPlace(Store store) async {
  if (!needsPlaceResolution(store)) return;
  try {
    if (store.located) {
      await savePlace(store, await placeAtPoint(store, store.latitude!, store.longitude!), followGps: store.followsGps);
    } else if (store.pincode.isNotEmpty) {
      await savePlace(store, await placeForPincode(store, store.pincode));
    } else {
      await savePlace(store, await placeForTown(store, store.town));
    }
  } catch (_) {
    /* Tried again on a later open. */
  }
}
