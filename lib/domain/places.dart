import 'dart:math' as math;

/// One post office of India from India Post's pincode
/// directory (see scripts/build-places.cjs): a place a customer can pick.
class Place {
  const Place({
    required this.name,
    required this.district,
    required this.state,
    required this.pincode,
    required this.village,
    this.head = false,
    required this.latitude,
    required this.longitude,
    required this.town,
  });
  final String name, district, state, pincode;
  // A village branch office rather than a town's head/sub office...
  final bool village;
  // ...and a head office, i.e. a main town or city.
  final bool head;
  // 0 when the directory has no (trustworthy) coordinates for it.
  final double latitude, longitude;
  // The town offers are matched on: itself, or the head office it belongs to
  // (Alcot Gardens -> Rajahmundry).
  final String town;

  bool get hasCoordinates => latitude != 0 || longitude != 0;

  /// "Rajahmundry, East Godavari" -- what the header shows once picked.
  String get label => town == name
      ? '$name, $district'
      : '$name ($town), $district';

  String get subtitle => '$district, $state • $pincode';
}

/// A whole district or state, offered by the admin's Location picker.
class PlaceArea {
  const PlaceArea.district(this.name, this.state) : isState = false;
  const PlaceArea.state(this.name) : state = name, isState = true;
  final String name, state;
  final bool isState;

  /// The token stored in an offer's `locations` for this area.
  String get token => isState ? 'state:$name' : 'district:$name';
}

/// The customer's place, as offers are matched against it. Empty strings mean
/// "unknown"; a customer with all three empty has not chosen a location.
class CustomerPlace {
  const CustomerPlace({this.town = '', this.district = '', this.state = ''});
  final String town, district, state;
  bool get isEmpty => town.isEmpty && district.isEmpty && state.isEmpty;
}

String _norm(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The token an admin stores to target one town: the name plus its district,
/// so two towns with the same name stay apart.
String townToken(Place place) => '${place.town} (${place.district})';

/// Whether one entry of an offer's `locations` list covers the customer:
/// `state:Telangana`, `district:East Godavari`, `Rajahmundry (East Godavari)`,
/// or the plain `Rajahmundry` older offers use.
bool locationTokenMatches(String token, CustomerPlace customer) {
  final wanted = _norm(token);
  if (wanted.isEmpty) return false;
  if (wanted.startsWith('state:')) {
    return customer.state.isNotEmpty &&
        wanted.substring(6).trim() == _norm(customer.state);
  }
  if (wanted.startsWith('district:')) {
    return customer.district.isNotEmpty &&
        wanted.substring(9).trim() == _norm(customer.district);
  }
  if (customer.town.isEmpty) return false;
  final town = _norm(customer.town);
  return wanted == town ||
      (customer.district.isNotEmpty &&
          wanted == '$town (${_norm(customer.district)})');
}

/// Readable form of a stored location token, for the admin's chips.
String describeLocationToken(String token) {
  final text = token.trim();
  final lower = text.toLowerCase();
  if (lower.startsWith('state:')) return 'All of ${text.substring(6).trim()}';
  if (lower.startsWith('district:')) {
    return 'All of ${text.substring(9).trim()} district';
  }
  return text;
}

class _Indexed {
  const _Indexed(this.place, this.lower, this.words, this.weight);
  final Place place;
  final String lower;
  final List<String> words;
  // How many pincodes the town spans: a city (Rajahmundry: 7) outranks a small
  // town (Rajampet: 1) when both match what was typed equally well.
  final int weight;
}

/// One state or union territory of `places.index.v1.json`: the file holding its places, its
/// districts, the map box of its offices and the first two digits of its pincodes.
class PlaceStateInfo {
  const PlaceStateInfo({
    required this.name,
    required this.file,
    required this.districts,
    required this.box,
    required this.pinPrefixes,
  });
  final String name, file;
  final List<String> districts;
  // [south, west, north, east]; all zeros when no office of the state has coordinates.
  final List<double> box;
  final List<int> pinPrefixes;

  bool boxContains(double latitude, double longitude, double marginDegrees) =>
      box.any((v) => v != 0) &&
      latitude >= box[0] - marginDegrees &&
      latitude <= box[2] + marginDegrees &&
      longitude >= box[1] - marginDegrees &&
      longitude <= box[3] + marginDegrees;
}

/// Every state and union territory, with its districts: small, loaded once, and enough to pick
/// which state files to download. Parses `web/data/places.index.v1.json`.
class PlacesManifest {
  PlacesManifest._(this.states);

  factory PlacesManifest.fromJson(Map<String, dynamic> json) {
    return PlacesManifest._([
      for (final raw in json['states'] as List)
        PlaceStateInfo(
          name: (raw as Map)['name'] as String,
          file: raw['file'] as String,
          districts: [for (final d in raw['districts'] as List) d as String],
          box: [for (final v in raw['box'] as List) (v as num).toDouble()],
          pinPrefixes: [for (final v in raw['pinPrefixes'] as List) v as int],
        ),
    ]);
  }

  final List<PlaceStateInfo> states;

  PlaceStateInfo? named(String name) {
    final wanted = _norm(name);
    for (final state in states) {
      if (_norm(state.name) == wanted) return state;
    }
    return null;
  }

  /// The states whose map box (plus a margin) holds the point, nearest box centre first.
  List<PlaceStateInfo> statesAt(
    double latitude,
    double longitude, {
    double marginDegrees = 0.6,
  }) {
    final found = [
      for (final state in states)
        if (state.boxContains(latitude, longitude, marginDegrees)) state,
    ];
    double away(PlaceStateInfo s) {
      final dLat = (s.box[0] + s.box[2]) / 2 - latitude;
      final dLng = (s.box[1] + s.box[3]) / 2 - longitude;
      return dLat * dLat + dLng * dLng;
    }

    found.sort((a, b) => away(a).compareTo(away(b)));
    return found;
  }

  /// The states whose pincodes start with the same two digits as [pincode].
  List<PlaceStateInfo> statesForPincode(String pincode) {
    if (!RegExp(r'^[1-9]\d{5}$').hasMatch(pincode)) return const [];
    final prefix = int.parse(pincode.substring(0, 2));
    return [
      for (final state in states)
        if (state.pinPrefixes.contains(prefix)) state,
    ];
  }

  /// Districts and states whose name matches what the admin typed (all of India).
  List<PlaceArea> searchAreas(String query) {
    final text = query.trim().toLowerCase();
    if (text.length < 2) return const [];
    bool hit(String name) {
      final lower = name.toLowerCase();
      return lower.startsWith(text) ||
          lower.split(RegExp(r'[\s\-]+')).any((w) => w.startsWith(text));
    }

    return [
      for (final state in states)
        if (hit(state.name)) PlaceArea.state(state.name),
      for (final state in states)
        for (final district in state.districts)
          if (hit(district)) PlaceArea.district(district, state.name),
    ];
  }
}

/// One file per state, each holding one state, joined into the single shape [PlacesIndex.fromJson]
/// reads: the states side by side, with the district numbers of every row moved to match.
Map<String, dynamic> mergePlaceFiles(List<Map<String, dynamic>> files) {
  final states = <String>[];
  final districts = <List<Object?>>[];
  final places = <List<Object?>>[];
  for (final file in files) {
    final stateOffset = states.length, districtOffset = districts.length;
    states.addAll([for (final s in file['states'] as List) s as String]);
    for (final d in file['districts'] as List) {
      districts.add([(d as List)[0], (d[1] as int) + stateOffset]);
    }
    for (final raw in file['places'] as List) {
      final row = List<Object?>.of(raw as List);
      row[1] = (row[1] as int) + districtOffset;
      places.add(row);
    }
  }
  return {'v': 1, 'states': states, 'districts': districts, 'places': places};
}

/// The directory, searchable. Pure (no I/O): build it from the parsed JSON.
class PlacesIndex {
  PlacesIndex._(this.states, this.districts, this._entries);

  /// Parses a places file (or several, joined by [mergePlaceFiles]).
  factory PlacesIndex.fromJson(Map<String, dynamic> json) {
    final states = [for (final s in json['states'] as List) s as String];
    final districts = [
      for (final d in json['districts'] as List)
        (name: (d as List)[0] as String, state: states[d[1] as int]),
    ];
    final pincodesOfTown = <String, Set<Object?>>{};
    for (final raw in json['places'] as List) {
      final row = raw as List;
      final town = row.length > 6 ? row[6] as String : row[0] as String;
      (pincodesOfTown['$town|${row[1]}'] ??= {}).add(row[2]);
    }
    final entries = <_Indexed>[];
    final coordinates = filledCoordinates(json['places'] as List);
    var rowNumber = -1;
    for (final raw in json['places'] as List) {
      rowNumber++;
      final row = raw as List;
      final name = row[0] as String;
      final district = districts[row[1] as int];
      final place = Place(
        name: name,
        district: district.name,
        state: district.state,
        pincode: '${row[2]}',
        village: row[3] == 1,
        head: row[3] == 2,
        latitude: coordinates[rowNumber].$1,
        longitude: coordinates[rowNumber].$2,
        town: row.length > 6 ? row[6] as String : name,
      );
      final lower = name.toLowerCase();
      entries.add(
        _Indexed(
          place,
          lower,
          lower.split(RegExp(r'[\s()/\-]+')),
          pincodesOfTown['${place.town}|${row[1]}']?.length ?? 1,
        ),
      );
    }
    return PlacesIndex._(states, districts, entries);
  }

  final List<String> states;
  final List<({String name, String state})> districts;
  final List<_Indexed> _entries;

  int get length => _entries.length;
  Iterable<Place> get places => _entries.map((e) => e.place);

  /// Places matching what the customer typed: a name (or the start of any
  /// word in it) or the start of a pincode. Towns before villages, names that
  /// start with the text before those that merely contain it.
  List<Place> search(String query, {int limit = 8}) {
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return const [];
    final scored = <(int, _Indexed)>[];
    if (RegExp(r'^\d+$').hasMatch(text)) {
      if (text.length < 3) return const [];
      for (final entry in _entries) {
        if (entry.place.pincode.startsWith(text)) {
          scored.add((_importance(entry.place), entry));
        }
      }
    } else {
      for (final entry in _entries) {
        int? rank;
        if (entry.lower.startsWith(text)) {
          rank = 0;
        } else if (entry.words.any((w) => w.startsWith(text))) {
          rank = 2;
        } else if (text.length >= 3 && entry.lower.contains(text)) {
          rank = 4;
        }
        if (rank != null) {
          scored.add((rank * 4 + _importance(entry.place), entry));
        }
      }
    }
    scored.sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      if (byRank != 0) return byRank;
      final byWeight = b.$2.weight.compareTo(a.$2.weight);
      if (byWeight != 0) return byWeight;
      final byLength = a.$2.lower.length.compareTo(b.$2.lower.length);
      return byLength != 0 ? byLength : a.$2.lower.compareTo(b.$2.lower);
    });
    // The same name can appear under several pincodes; keep them all but cap.
    return [for (final item in scored.take(limit)) item.$2.place];
  }

  /// Districts and states whose name matches what the admin typed.
  List<PlaceArea> searchAreas(String query) {
    final text = query.trim().toLowerCase();
    if (text.length < 2) return const [];
    bool hit(String name) {
      final lower = name.toLowerCase();
      return lower.startsWith(text) ||
          lower.split(RegExp(r'[\s\-]+')).any((w) => w.startsWith(text));
    }

    return [
      for (final state in states)
        if (hit(state)) PlaceArea.state(state),
      for (final district in districts)
        if (hit(district.name)) PlaceArea.district(district.name, district.state),
    ];
  }

  /// The town nearest to a GPS fix, from the directory's own coordinates.
  /// Null when the nearest place with coordinates is more than [maxKm] away
  /// (the customer isn't in any state loaded).
  Place? nearestTown(double latitude, double longitude, {double maxKm = 60}) {
    Place? bestTown, bestAny;
    var townKm = double.infinity, anyKm = double.infinity;
    for (final entry in _entries) {
      final place = entry.place;
      if (!place.hasCoordinates) continue;
      // The directory gives many sub offices their town's own coordinates, so
      // ties are common; a head office gets a small head start.
      final km =
          distanceKmBetween(latitude, longitude, place.latitude, place.longitude) -
          (place.head ? 3 : 0);
      if (km < anyKm) {
        anyKm = km;
        bestAny = place;
      }
      if (!place.village && km < townKm) {
        townKm = km;
        bestTown = place;
      }
    }
    // A village a good deal closer than any town still tells us the town
    // it belongs to; otherwise the nearest town itself.
    final best = (bestTown != null && townKm <= anyKm + 5) ? bestTown : bestAny;
    final distance = best == bestTown ? townKm : anyKm;
    return best != null && distance <= maxKm ? best : null;
  }

  // Head offices (main towns) first, then sub offices, then villages.
  static int _importance(Place place) =>
      place.head ? 0 : (place.village ? 2 : 1);

  /// The place a pincode belongs to: its head office if it has one, else its
  /// first town-type office, else any office with that pincode. Null when the
  /// pincode is not in the states loaded.
  Place? byPincode(String pincode) {
    Place? town, any;
    for (final entry in _entries) {
      final place = entry.place;
      if (place.pincode != pincode) continue;
      if (place.head) return place;
      if (!place.village) town ??= place;
      any ??= place;
    }
    return town ?? any;
  }

  /// A town-type place with this exact name, for resolving a stored town.
  Place? townNamed(String name, {String? district}) {
    final wanted = _norm(name);
    for (final entry in _entries) {
      final place = entry.place;
      if (!place.village &&
          _norm(place.name) == wanted &&
          (district == null || _norm(place.district) == _norm(district))) {
        return place;
      }
    }
    return null;
  }
}

/// A coordinate for every row of the directory. About a quarter of the rows have none (stored as
/// 0, 0), so each of those gets an estimate from its neighbours: the other offices with the same
/// pincode, else the same first 5 digits, else the first 4, else the district's average. That way the
/// nearest place to a GPS fix can be found everywhere. functions/places.js does exactly the same
/// (a test keeps the two identical).
List<(double, double)> filledCoordinates(List places) {
  bool has(num lat, num lng) => !(lat == 0 && lng == 0);
  double round3(double value) => (value * 1000).round() / 1000;
  List<String> keysOf(List row) {
    final pin = '${row[2]}';
    return [
      'p$pin',
      'a${pin.substring(0, math.min(5, pin.length))}',
      'b${pin.substring(0, math.min(4, pin.length))}',
      'd${row[1]}',
    ];
  }

  final sums = <String, List<double>>{};
  for (final raw in places) {
    final row = raw as List;
    if (!has(row[4] as num, row[5] as num)) continue;
    for (final key in keysOf(row)) {
      final have = sums.putIfAbsent(key, () => [0, 0, 0]);
      have[0] += (row[4] as num).toDouble();
      have[1] += (row[5] as num).toDouble();
      have[2] += 1;
    }
  }
  return [
    for (final raw in places)
      () {
        final row = raw as List;
        final lat = (row[4] as num).toDouble(), lng = (row[5] as num).toDouble();
        if (has(lat, lng)) return (lat, lng);
        for (final key in keysOf(row)) {
          final found = sums[key];
          if (found != null) {
            return (round3(found[0] / found[2]), round3(found[1] / found[2]));
          }
        }
        return (0.0, 0.0);
      }(),
  ];
}

/// Great-circle distance in kilometres.
double distanceKmBetween(double aLat, double aLng, double bLat, double bLng) {
  const radians = math.pi / 180;
  final dLat = (bLat - aLat) * radians, dLng = (bLng - aLng) * radians;
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(aLat * radians) *
          math.cos(bLat * radians) *
          math.pow(math.sin(dLng / 2), 2);
  return 12742 * math.asin(math.sqrt(h.toDouble()));
}
