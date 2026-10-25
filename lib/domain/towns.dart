import 'catalog.dart';
import 'places.dart';

/// A town the admin serves, from `settings/business.serviceTowns`.
class ServiceTown {
  const ServiceTown(this.name, [this.pincodes = const []]);
  final String name;
  final List<String> pincodes;
}

/// Placeholder address texts the location dialog writes when it has no real
/// place name (GPS / dropped pin); never a town.
const _placeholderAddresses = {'current gps location', 'pinned location'};

String _norm(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The town a place name is in, for comparing: the India Post directory names some localities with their town in brackets
/// ("Krishna Bazar (Narsipatnam)" is in Narsipatnam), so a customer located there sees the town's shops. Lower-cased.
String townKey(String town) {
  final bracket = RegExp(r'\(([^)]+)\)').firstMatch(town);
  return _norm(bracket != null ? bracket.group(1)! : town);
}

/// Parses the admin's `serviceTowns` setting: comma- or newline-separated
/// town names, each optionally followed by `=pin1|pin2` so a pincode alone can
/// pick the town, e.g. `Narsipatnam=531116|531115, Anakapalle=531001`.
List<ServiceTown> parseServiceTowns(String raw) {
  final towns = <ServiceTown>[];
  final seen = <String>{};
  for (final part in raw.split(RegExp(r'[,\n]'))) {
    final text = part.trim();
    if (text.isEmpty) continue;
    final equals = text.indexOf('=');
    final name = (equals < 0 ? text : text.substring(0, equals)).trim();
    if (name.isEmpty || !seen.add(_norm(name))) continue;
    final pins = equals < 0
        ? <String>[]
        : text
              .substring(equals + 1)
              .split(RegExp(r'[|\s]+'))
              .where((p) => RegExp(r'^\d{6}$').hasMatch(p))
              .toList();
    towns.add(ServiceTown(name, pins));
  }
  return towns;
}

/// The comma/newline separated names an offer's `locations` field lists.
List<String> parseLocationList(String raw) => [
  for (final part in raw.split(RegExp(r'[,\n]')))
    if (part.trim().isNotEmpty) part.trim(),
];

/// Works out the customer's town from what they entered. An explicit [town]
/// (picked from the town list, or the first part of a searched place name)
/// wins; otherwise a configured town matching the pincode or any part of the
/// address does. Returns '' when nothing identifies a town -- free-typed
/// street text is never guessed into a town name.
String resolveTown({
  String? town,
  required String pincode,
  required String address,
  required List<ServiceTown> towns,
}) {
  final explicit = (town ?? '').trim();
  if (explicit.isNotEmpty) return _canonical(explicit, towns);
  final pin = pincode.trim();
  if (pin.isNotEmpty) {
    for (final candidate in towns) {
      if (candidate.pincodes.contains(pin)) return candidate.name;
    }
  }
  final text = address.trim();
  if (text.isEmpty || _placeholderAddresses.contains(_norm(text))) return '';
  for (final segment in text.split(',')) {
    final match = _matchConfigured(segment, towns);
    if (match != null) return match.name;
  }
  return '';
}

ServiceTown? _matchConfigured(String text, List<ServiceTown> towns) {
  final wanted = _norm(text);
  if (wanted.isEmpty) return null;
  for (final candidate in towns) {
    if (_norm(candidate.name) == wanted) return candidate;
  }
  return null;
}

/// Uses the admin's spelling of a town when the name matches a configured
/// one, so "narsipatnam" and "Narsipatnam" are the same town everywhere.
String _canonical(String name, List<ServiceTown> towns) =>
    _matchConfigured(name, towns)?.name ?? name.trim();

/// First part of a searched place name ("Narsipatnam, Anakapalli district,
/// ..." -> "Narsipatnam"); the configured spelling when that part is one.
String townFromPlaceName(String displayName, List<ServiceTown> towns) {
  final segments = displayName
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (segments.isEmpty) return '';
  for (final segment in segments) {
    final match = _matchConfigured(segment, towns);
    if (match != null) return match.name;
  }
  return segments.first;
}

/// True when [promotion] is meant for the customer's place. Its `locations`
/// list holds towns ("Rajahmundry (East Godavari)", or just "Rajahmundry" in
/// older offers), whole districts ("district:East Godavari") and whole states
/// ("state:Telangana"); see [locationTokenMatches]. A promotion without a
/// list is general (every town).
bool promotionListsTown(
  Entry promotion,
  String town, {
  String district = '',
  String state = '',
}) {
  final customer = CustomerPlace(town: town, district: district, state: state);
  return parseLocationList(
    promotion.text('locations'),
  ).any((token) => locationTokenMatches(token, customer));
}

bool promotionIsGeneral(Entry promotion) =>
    parseLocationList(promotion.text('locations')).isEmpty;

/// The promotions to show for a customer's place:
/// - no place chosen yet: only the general (all-town) ones -- an offer made for
///   one town must never reach a customer who has not chosen that location;
///   [TownOffers.hiddenForLocation] counts those held back, so the page can ask
///   the customer to choose a location;
/// - otherwise only those listing the town, its district or its state;
/// - if none do, the general ones instead, flagged via [TownOffers.usedGeneral];
/// - if there are no general ones either, an empty list (the page then shows
///   its default "no offers" message rather than empty boxes).
/// [showAll] (the admin's editor preview) skips the filter entirely.
class TownOffers {
  const TownOffers(
    this.entries, {
    this.usedGeneral = false,
    this.hiddenForLocation = 0,
  });
  final List<Entry> entries;
  final bool usedGeneral;
  final int hiddenForLocation;
}

TownOffers promotionsForTown(
  List<Entry> promotions,
  String town, {
  String district = '',
  String state = '',
  bool showAll = false,
}) {
  if (showAll) return TownOffers(promotions);
  if (town.trim().isEmpty && district.trim().isEmpty && state.trim().isEmpty) {
    final general = promotions.where(promotionIsGeneral).toList();
    return TownOffers(
      general,
      hiddenForLocation: promotions.length - general.length,
    );
  }
  final local = promotions
      .where((e) => promotionListsTown(e, town, district: district, state: state))
      .toList();
  if (local.isNotEmpty) return TownOffers(local);
  final general = promotions.where(promotionIsGeneral).toList();
  return TownOffers(general, usedGeneral: general.isNotEmpty);
}
