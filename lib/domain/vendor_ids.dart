import 'catalog.dart';

// Vendor IDs look like VEN-NRPM-116-325: VEN, the town's four-letter city code, the last three digits of the shop's pincode, and a
// unique three-digit number. The server makes them (functions/vendor-id.js, the same default table and rules); the admin edits the
// city-code table in Settings > City codes (settings/cityCodes.rows).

const cityCodesDoc = 'cityCodes';

class CityCodeRow {
  const CityCodeRow(this.town, this.code, [this.pincodes = '']);
  final String town, code;

  /// Optional pincodes that always use this code (for a pincode the directory files under another town), comma-separated.
  final String pincodes;

  Map<String, String> toJson() => {'town': town.trim(), 'code': code.trim().toUpperCase(), 'pincodes': pincodes.trim()};
}

const defaultCityCodes = [CityCodeRow('Narsipatnam', 'NRPM'), CityCodeRow('Tuni', 'TUNI'), CityCodeRow('Rajahmundry', 'RAJH')];

final vendorIdPattern = RegExp(r'^VEN-[A-Z]{4}-\d{3}-\d{3}$');
final _cityCode = RegExp(r'^[A-Z]{4}$');

bool validCityCode(String code) => _cityCode.hasMatch(code.trim().toUpperCase());

/// The table as saved (only valid rows), or the built-in one when nothing valid is saved, exactly as the server reads it.
List<CityCodeRow> cityCodeRows(List<Entry> settings) {
  final saved = settings.where((e) => e.id == cityCodesDoc).firstOrNull?.data['rows'];
  final rows = [
    if (saved is List)
      for (final row in saved)
        if (row is Map)
          CityCodeRow('${row['town'] ?? ''}'.trim(), '${row['code'] ?? ''}'.trim().toUpperCase(), '${row['pincodes'] ?? ''}'),
  ].where((r) => r.town.isNotEmpty && validCityCode(r.code)).toList();
  return rows.isEmpty ? defaultCityCodes : rows;
}

/// What is wrong with a table the admin wants to save (empty when it can be saved).
List<String> cityCodeProblems(List<CityCodeRow> rows) {
  final problems = <String>[];
  final towns = <String>{}, codes = <String>{};
  for (final (i, row) in rows.indexed) {
    final n = i + 1;
    if (row.town.trim().isEmpty) problems.add('Row $n: enter the town name.');
    if (!validCityCode(row.code)) problems.add('Row $n: the code must be exactly four letters (A-Z).');
    if (row.town.trim().isNotEmpty && !towns.add(row.town.trim().toLowerCase())) problems.add('Row $n: ${row.town.trim()} is in the table twice.');
    if (validCityCode(row.code) && !codes.add(row.code.trim().toUpperCase())) problems.add('Row $n: the code ${row.code.trim().toUpperCase()} is already used by another town.');
    for (final pin in row.pincodes.split(RegExp(r'[^0-9]+')).where((p) => p.isNotEmpty)) {
      if (pin.length != 6) problems.add('Row $n: "$pin" is not a six-digit pincode.');
    }
  }
  if (rows.isEmpty) problems.add('Add at least one town.');
  return problems;
}
