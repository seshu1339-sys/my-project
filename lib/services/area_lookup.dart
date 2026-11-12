import '../data/store.dart';
import '../domain/area_names.dart';
import '../domain/places.dart';
import 'geocoding.dart';
import 'places_directory.dart';

// ---------------------------------------------------------------------------------------------
// Turns however the customer gave their place (GPS, a point on the map, a place picked from the list, a pincode, a town) into ONE
// place: the point what they see is measured from (lib/domain/reach.dart), and the AREA name shown everywhere (lib/domain/area_names.dart).
//
// The area of a point: first what OpenStreetMap calls it (suburb, quarter, neighbourhood, hamlet, village: the names people use),
// then the nearest post office within 1.5 km that has a map position of its own (many offices only carry their town's point, which
// says nothing about the part of town), else the town. The admin's Settings > Area names renames or blocks names on the way.
// ---------------------------------------------------------------------------------------------

/// One place, ready to save with [savePlace].
class FoundPlace {
  const FoundPlace({
    required this.latitude,
    required this.longitude,
    this.area = '',
    this.town = '',
    this.district = '',
    this.state = '',
    this.pincode = '',
  });
  final double latitude, longitude;
  final String area, town, district, state, pincode;
}

typedef AreaLookUp = Future<OsmArea?> Function(double latitude, double longitude);
typedef DirectoryAtPoint = Future<PlacesIndex?> Function(double latitude, double longitude);

Future<PlacesIndex?> _directoryAt(double latitude, double longitude) async {
  try {
    return await PlacesDirectory.instance.loadForPoint(latitude, longitude);
  } catch (_) {
    return null;
  }
}

AreaNames _names(Store store) => AreaNames.from(store.entries('settings'));

/// The place at a GPS fix or a point on the map. Never throws: without the directory and OpenStreetMap the point still counts, only
/// with no name. [lookUp] and [directory] are for tests (default: OpenStreetMap and the India Post directory).
Future<FoundPlace> placeAtPoint(Store store, double latitude, double longitude, {AreaLookUp? lookUp, DirectoryAtPoint? directory}) async {
  final index = await (directory ?? _directoryAt)(latitude, longitude);
  final nearest = index?.nearestTown(latitude, longitude);
  final office = index?.nearestOwnSpot(latitude, longitude);
  OsmArea? osm;
  try {
    osm = await (lookUp ?? NominatimGeocoder(contactEmail: store.business.text('supportEmail')).reverseArea)(latitude, longitude);
  } catch (_) {
    osm = null;
  }
  final town = nearest?.town ?? osm?.town ?? '';
  final district = nearest?.district ?? osm?.district ?? '';
  final state = nearest?.state ?? osm?.state ?? '';
  return FoundPlace(
    latitude: latitude,
    longitude: longitude,
    area: chooseArea([...?osm?.areas, ?office?.name], town: town, district: district, state: state, names: _names(store)),
    town: town,
    district: district,
    state: state,
    pincode: nearest?.pincode ?? osm?.pincode ?? '',
  );
}

/// A place picked from the directory list ("Kancharapalem, Visakhapatnam"): its own name is the area unless it is just the town.
/// Throws when the directory has no map position for it at all.
FoundPlace placeFromDirectory(Store store, Place place) {
  if (!place.hasCoordinates) throw StateError('This place has no map position yet. Use GPS, or choose a place nearby.');
  return FoundPlace(
    latitude: place.latitude,
    longitude: place.longitude,
    area: chooseArea([place.name], town: place.town, district: place.district, state: place.state, names: _names(store)),
    town: place.town,
    district: place.district,
    state: place.state,
    pincode: place.pincode,
  );
}

/// A typed pincode: the point of its main office, and its area when the pincode has a single post office (else the town's name,
/// rather than a guess). Throws when the pincode is not known. [directory] is for tests.
Future<FoundPlace> placeForPincode(Store store, String pincode, {Future<PlacesIndex> Function(String pincode)? directory}) async {
  final pin = pincode.trim();
  if (!RegExp(r'^\d{6}$').hasMatch(pin)) throw StateError('Enter a valid six-digit pincode.');
  final PlacesIndex index;
  try {
    index = await (directory ?? PlacesDirectory.instance.loadForPincode)(pin);
  } catch (_) {
    throw StateError('The pincode list could not be loaded. Check your connection and try again.');
  }
  final main = index.byPincode(pin);
  if (main == null || !main.hasCoordinates) throw StateError('This pincode was not found. Check it, or use GPS.');
  // One office names the pincode's area only when it is the pincode's one town office: a pincode with a head office is the town's
  // own (its sub offices are only parts of it), and several offices would be a guess.
  final all = index.officesOf(pin);
  final offices = [for (final p in all) if (!p.head && !p.village) p];
  final single = !all.any((p) => p.head) && offices.length == 1 ? offices.single : null;
  return FoundPlace(
    latitude: (single ?? main).hasCoordinates ? (single ?? main).latitude : main.latitude,
    longitude: (single ?? main).hasCoordinates ? (single ?? main).longitude : main.longitude,
    area: chooseArea([?single?.name], town: main.town, district: main.district, state: main.state, names: _names(store)),
    town: main.town,
    district: main.district,
    state: main.state,
    pincode: pin,
  );
}

/// A town chosen by name (the admin's town list): the town's own point. Throws when the directory does not know it.
Future<FoundPlace> placeForTown(Store store, String town, {Future<PlacesIndex> Function()? directory}) async {
  final PlacesIndex index;
  try {
    index = await (directory ?? PlacesDirectory.instance.load)();
  } catch (_) {
    throw StateError('The town list could not be loaded. Check your connection and try again.');
  }
  final place = index.townNamed(town);
  if (place == null || !place.hasCoordinates) throw StateError('"$town" was not found on the map. Use GPS or a pincode.');
  return FoundPlace(
    latitude: place.latitude,
    longitude: place.longitude,
    area: chooseArea(const [], town: place.town, names: _names(store)),
    town: place.town,
    district: place.district,
    state: place.state,
    pincode: place.pincode,
  );
}

/// Saves [place] as the customer's place: the area, offers, shops and products change at once. [followGps] is true only for GPS
/// (the place then moves with the phone, lib/main.dart). The typed address (for delivery) is kept unless [address] replaces it.
Future<void> savePlace(Store store, FoundPlace place, {bool followGps = false, String? address}) => store.setLocation(
  place.pincode.isNotEmpty ? place.pincode : store.pincode,
  address ?? store.address,
  lat: place.latitude,
  lng: place.longitude,
  town: place.town,
  district: place.district,
  state: place.state,
  area: place.area,
  followGps: followGps,
);
