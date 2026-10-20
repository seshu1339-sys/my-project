import '../data/store.dart';
import '../domain/towns.dart';
import 'geocoding.dart';

/// The town for a GPS fix or dropped pin: looked up by reverse geocoding
/// (free OpenStreetMap Nominatim, same as place search). '' when it can't be
/// found, which the storefront treats as "no town" -- general offers only.
Future<String> townForPoint(Store store, double latitude, double longitude) =>
    NominatimGeocoder(
      contactEmail: store.business.text('supportEmail'),
    ).reverseTown(latitude, longitude);

/// The town for a searched place: the admin's own spelling when one of the
/// place name's parts is a configured town, else the name's first part.
String townForPlace(Store store, NominatimPlace place) => townFromPlaceName(
  place.displayName,
  parseServiceTowns(store.business.text('serviceTowns')),
);
