/// Language codes in the fixed column order used by every translation row
/// (the English text comes first, then one entry per code below).
const translationColumns = [
  'hi',
  'te',
  'ta',
  'kn',
  'bn',
  'mr',
  'gu',
  'pa',
  'ml',
  'or',
];

/// Turns compact rows -- `[english, hi, te, ta, kn, bn, mr, gu, pa, ml, or]`
/// -- into the English -> {language code: text} shape strings.dart looks up.
/// A row of the wrong length is a bug, so it fails loudly instead of silently
/// shifting every later language by one.
Map<String, Map<String, String>> buildTranslations(List<List<String>> rows) {
  final result = <String, Map<String, String>>{};
  for (final row in rows) {
    if (row.length != translationColumns.length + 1) {
      throw StateError(
        'Translation row "${row.first}" has ${row.length - 1} languages, '
        'expected ${translationColumns.length}.',
      );
    }
    result[row.first] = {
      for (var i = 0; i < translationColumns.length; i++)
        translationColumns[i]: row[i + 1],
    };
  }
  return result;
}
