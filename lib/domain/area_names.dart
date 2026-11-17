import 'catalog.dart';

// ---------------------------------------------------------------------------------------------
// The customer's AREA: the name everyone calls the part of town they are in (Kancharapalem, Gurudwara), shown in the location box,
// the greeting and "Today's ... Offers" (owner, 11 Nov 2026). Never a house number, a street or a full address, and never a big city
// such as Visakhapatnam when a nearer name is known; when no area name is found, the town's own name.
//
// Settings > Area names (`settings/areaNames`) lets the admin fix what the maps call a place:
//   renames   one per line, "map name = shown name"   (Kancharapalem S.O = Kancharapalem, Gurudwara Junction = Gurudwara)
//   blocked   one per line, names never shown as an area (Visakhapatnam): the next nearer name is used instead
// ---------------------------------------------------------------------------------------------

const areaNamesId = 'areaNames';

/// Same name, ignoring case, dots and extra spaces ("Kancharapalem S.O" and "kancharapalem s.o.").
String areaKey(String name) => name.toLowerCase().replaceAll('.', '').replaceAll(RegExp(r'\s+'), ' ').trim();

class AreaNames {
  const AreaNames({this.renames = const {}, this.blocked = const {}});

  /// The admin's Settings > Area names, or none.
  factory AreaNames.from(List<Entry> settings) {
    final doc = settings.where((e) => e.id == areaNamesId).firstOrNull;
    return AreaNames.parse(renames: doc?.text('renames') ?? '', blocked: doc?.text('blocked') ?? '');
  }

  factory AreaNames.parse({String renames = '', String blocked = ''}) => AreaNames(
    renames: {for (final (from, to) in parseAreaRenames(renames)) areaKey(from): to},
    blocked: {for (final name in parseBlockedAreas(blocked)) areaKey(name)},
  );

  /// Map name (by [areaKey]) -> the name to show.
  final Map<String, String> renames;

  /// Names (by [areaKey]) never shown as an area.
  final Set<String> blocked;

  /// The admin's name for [name], or null when there is none.
  String? renamed(String name) => renames[areaKey(name)];

  bool isBlocked(String name) => blocked.contains(areaKey(name));
}

/// The rows of the renames text: "map name = shown name" per line; lines without both sides are skipped.
List<(String, String)> parseAreaRenames(String text) => [
  for (final line in text.split('\n'))
    if (line.contains('='))
      if (line.substring(0, line.indexOf('=')).trim() case final from when from.isNotEmpty)
        if (line.substring(line.indexOf('=') + 1).trim() case final to when to.isNotEmpty) (from, to),
];

/// The blocked names: one per line (commas also separate), blanks skipped.
List<String> parseBlockedAreas(String text) => [
  for (final part in text.split(RegExp(r'[\n,]')))
    if (part.trim().isNotEmpty) part.trim(),
];

/// The renames as saved: one "map name = shown name" per line.
String areaRenamesText(Iterable<(String, String)> rows) => [
  for (final (from, to) in rows)
    if (from.trim().isNotEmpty && to.trim().isNotEmpty) '${from.trim()} = ${to.trim()}',
].join('\n');

/// The name without what the post office or the map adds to it: the bracketed town ("Anandapuram S.O (Visakhapatnam)") and the office
/// type (S.O, B.O, H.O, Sub Office...).
String cleanAreaName(String raw) {
  var name = raw.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  name = name.replaceAll(RegExp(r'\b(s\.?\s?o|b\.?\s?o|h\.?\s?o|sub\s+office|branch\s+office|head\s+office)\.?\s*$', caseSensitive: false), ' ');
  return name.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// A name people would call an area: it has letters, and it is not an office's or a council's number ("Ward 26", "Zone 3").
bool usableAreaName(String name) {
  if (!RegExp(r'[A-Za-zऀ-෿]').hasMatch(name)) return false;
  return !RegExp(r'^(ward|zone|division|circle)\b', caseSensitive: false).hasMatch(name.trim());
}

/// The area to show: the first of [candidates] (nearest / most specific first) that is a real area name, not blocked by the admin and
/// not just the town, district or state again; else the town. The admin's renames apply to both.
String chooseArea(
  Iterable<String> candidates, {
  required String town,
  String district = '',
  String state = '',
  AreaNames names = const AreaNames(),
}) {
  bool same(String a, String b) => b.isNotEmpty && areaKey(a) == areaKey(b);
  for (final raw in candidates) {
    if (raw.trim().isEmpty) continue;
    final cleaned = cleanAreaName(raw);
    final name = names.renamed(raw) ?? names.renamed(cleaned) ?? cleaned;
    if (!usableAreaName(name)) continue;
    if (names.isBlocked(raw) || names.isBlocked(cleaned) || names.isBlocked(name)) continue;
    if (same(name, town) || same(name, district) || same(name, state)) continue;
    return name;
  }
  final cleanTown = cleanAreaName(town);
  return names.renamed(town) ?? names.renamed(cleanTown) ?? cleanTown;
}
