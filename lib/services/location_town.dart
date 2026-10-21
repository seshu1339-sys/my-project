import '../data/store.dart';
import '../domain/places.dart';
import '../domain/towns.dart';
import 'geocoding.dart';
import 'places_directory.dart';

/// The town for a GPS fix or dropped pin: looked up by reverse geocoding
/// (free OpenStreetMap Nominatim, same as place search). '' when it can't be
/// found, which the storefront treats as "no town" -- general offers only.
Future<String> townForPoint(Store store, double latitude, double longitude) =>
    NominatimGeocoder(
      contactEmail: store.business.text('supportEmail'),
    ).reverseTown(latitude, longitude);

/// The directory place nearest to a GPS fix (loads the directory, which stays
/// cached afterwards), or null when it can't be loaded or the fix is outside
/// Andhra Pradesh / Telangana.
Future<Place?> nearestPlaceFor(double latitude, double longitude) async {
  try {
    return (await PlacesDirectory.instance.load()).nearestTown(latitude, longitude);
  } catch (_) {
    return null;
  }
}

/// The pincode to store for a GPS fix: the typed one when it belongs to the same town as
/// the nearest place, else that place's own -- so a stale pincode left from another town
/// never decides which offers (or push notifications) the customer gets.
String pincodeForGps(String typed, Place? nearest) {
  if (nearest == null) return typed;
  if (typed.isEmpty) return nearest.pincode;
  final known = PlacesDirectory.instance.ready?.byPincode(typed);
  return known != null && known.town == nearest.town ? typed : nearest.pincode;
}

/// The town for a searched place: the admin's own spelling when one of the
/// place name's parts is a configured town, else the name's first part.
String townForPlace(Store store, NominatimPlace place) => townFromPlaceName(
  place.displayName,
  parseServiceTowns(store.business.text('serviceTowns')),
);
