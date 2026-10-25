import '../domain/places.dart';
import 'geocoding.dart';
import 'location_town.dart';

/// The address and pincode worked out from a GPS point, for a vendor's shop or a service provider's house.
class GpsAddress {
  const GpsAddress(this.text, this.pincode);
  final String text, pincode;
}

/// The street address from OpenStreetMap, the pincode from the India Post directory (OpenStreetMap's postcodes are often wrong here;
/// the directory is also what the Vendor ID uses). Falls back to the directory's town and district when OpenStreetMap has nothing.
/// [lookUp] and [findPlace] are for tests (default: OpenStreetMap and the directory).
Future<GpsAddress> addressForPoint(
  double latitude,
  double longitude, {
  String contactEmail = '',
  Future<ReverseAddress?> Function(double latitude, double longitude)? lookUp,
  Future<Place?> Function(double latitude, double longitude)? findPlace,
}) async {
  final found = await (lookUp ?? NominatimGeocoder(contactEmail: contactEmail).reverseAddress)(latitude, longitude);
  final place = await (findPlace ?? nearestPlaceFor)(latitude, longitude);
  final pin = (place != null && place.pincode.isNotEmpty) ? place.pincode : (found?.pincode ?? '');
  var text = found?.text ?? (place == null ? '' : [place.town, place.district].where((p) => p.isNotEmpty).join(', '));
  if (found != null && pin.isNotEmpty) {
    text = found.pincode.isNotEmpty ? text.replaceAll(found.pincode, pin) : (text.contains(pin) ? text : '$text, $pin');
  }
  return GpsAddress(text, pin);
}
