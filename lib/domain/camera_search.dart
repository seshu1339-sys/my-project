// Camera search (owner, 18 Nov 2026: "cost cuts" part 1): the phone names what is in the photo with Google ML Kit image labeling
// (on the phone, free, offline; the photo never leaves the phone), and these rules turn those names into what opens:
//   * one item of the admin's Item Catalog (productImageLibrary: its English name, or a Telugu / other word in its tags), or a
//     table row that points to one item: that item's shops open directly;
//   * else the category the labels point to (the admin's "Camera label -> Category" table first, then the category names
//     themselves, so "Fruit" finds "Fruits"): that category opens;
//   * else nothing: every category button is shown.
// The table and the "Camera search may use AI" switch are settings/cameraSearch {aiAllowed, rows: [{label, categoryId, itemId}]}.
// AI is never used unless the admin switches it on, and then only when the labels match nothing.
// Only counts are kept: "camera_label" usage events, key "<label>|<what opened>" (functions/usage.js). No photo is stored.
import 'catalog.dart';

const cameraSearchSettingsId = 'cameraSearch';

/// The labels the phone gives below this confidence are not used.
const cameraMinConfidence = 0.55;

/// One name the phone gave the photo, with how sure it is (0 to 1).
class CameraLabel {
  const CameraLabel(this.text, this.confidence);
  final String text;
  final double confidence;
}

/// One row of the admin's table: a label the phone gives, and the category (or one Item Catalog item) it opens.
class CameraRow {
  const CameraRow(this.label, {this.categoryId = '', this.itemId = ''});
  final String label, categoryId, itemId;

  static CameraRow? fromMap(Object? value) {
    if (value is! Map) return null;
    final label = '${value['label'] ?? ''}'.trim();
    final categoryId = '${value['categoryId'] ?? ''}'.trim();
    final itemId = '${value['itemId'] ?? ''}'.trim();
    if (label.isEmpty || (categoryId.isEmpty && itemId.isEmpty)) return null;
    return CameraRow(label, categoryId: categoryId, itemId: itemId);
  }

  Map<String, String> toMap() => {'label': label, 'categoryId': categoryId, 'itemId': itemId};
}

/// The owner's starting table (18 Nov 2026). There is no "Kirana" category: rice and packaged food open Grocery & Staples.
const defaultCameraRows = <CameraRow>[
  CameraRow('bucket', categoryId: 'cat-plastics'),
  CameraRow('container', categoryId: 'cat-plastics'),
  CameraRow('plastic', categoryId: 'cat-plastics'),
  CameraRow('bangle', categoryId: 'cat-fancy'),
  CameraRow('cosmetics', categoryId: 'cat-fancy'),
  CameraRow('jewellery', categoryId: 'cat-fancy'),
  CameraRow('jewelry', categoryId: 'cat-fancy'),
  CameraRow('necklace', categoryId: 'cat-fancy'),
  CameraRow('earrings', categoryId: 'cat-fancy'),
  CameraRow('rice', categoryId: 'cat-grocery-staples'),
  CameraRow('packaged goods', categoryId: 'cat-grocery-staples'),
  CameraRow('packaged food', categoryId: 'cat-grocery-staples'),
  CameraRow('clothing', categoryId: 'cat-clothes'),
  CameraRow('shirt', categoryId: 'cat-clothes'),
  CameraRow('saree', categoryId: 'cat-clothes'),
  CameraRow('sari', categoryId: 'cat-clothes'),
  CameraRow('dress', categoryId: 'cat-clothes'),
  CameraRow('jeans', categoryId: 'cat-clothes'),
  CameraRow('textile', categoryId: 'cat-clothes'),
  CameraRow('vegetable', categoryId: 'cat-vegetables'),
  CameraRow('fruit', categoryId: 'cat-fruits'),
];

/// settings/cameraSearch among the settings records (null when the admin never saved it).
Entry? cameraSettingsOf(List<Entry> settings) => settings.where((e) => e.id == cameraSearchSettingsId).firstOrNull;

/// The admin's table; the owner's starting table until the admin saves one.
List<CameraRow> cameraRowsOf(Entry? settings) {
  final rows = settings?.data['rows'];
  if (rows is! List) return defaultCameraRows;
  return [for (final r in rows) ?CameraRow.fromMap(r)];
}

/// "Camera search may use AI": off unless the admin switched it on.
bool cameraAiAllowed(Entry? settings) => settings?.data['aiAllowed'] == true;

enum CameraMatchKind { item, category, none }

/// What a photo opens. [label] is the phone's label that decided it ('' for none).
class CameraMatch {
  const CameraMatch.item(this.itemId, this.itemName, this.label) : kind = CameraMatchKind.item, categoryId = '';
  const CameraMatch.category(this.categoryId, this.label) : kind = CameraMatchKind.category, itemId = '', itemName = '';
  const CameraMatch.none() : kind = CameraMatchKind.none, itemId = '', itemName = '', categoryId = '', label = '';
  final CameraMatchKind kind;
  final String itemId, itemName, categoryId, label;
}

/// Lower case words (English or Telugu letters), each made singular: "Fresh & Vegetables" -> [fresh, vegetable].
List<String> cameraWords(String text) => [
  for (final w in text.toLowerCase().split(RegExp(r'[^a-z0-9ఀ-౿]+'))) if (w.isNotEmpty) _singular(w),
];

String _singular(String w) {
  if (w.length <= 3 || !RegExp(r'^[a-z]+$').hasMatch(w)) return w;
  if (w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.endsWith('oes') || RegExp(r'(s|x|ch|sh)es$').hasMatch(w)) return w.substring(0, w.length - 2);
  if (w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
  return w;
}

String _phrase(String text) => cameraWords(text).join(' ');

/// [label] is [row]: the same words, or a one-word row inside a longer label ("vegetable" in "Leaf vegetable").
bool _rowFits(String row, String label) {
  if (row.isEmpty) return false;
  if (row == label) return true;
  return !row.contains(' ') && label.split(' ').contains(row);
}

/// Turns the phone's [labels] into what opens. [items] are the Item Catalog (productImageLibrary), [categories] the categories.
CameraMatch matchCameraLabels(
  List<CameraLabel> labels, {
  required List<CameraRow> rows,
  required List<Entry> items,
  required List<Entry> categories,
  double minConfidence = cameraMinConfidence,
}) {
  final sure = [for (final l in labels) if (l.confidence >= minConfidence && _phrase(l.text).isNotEmpty) l]
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  if (sure.isEmpty) return const CameraMatch.none();
  bool on(Entry e) => e.data['active'] != false;
  final liveItems = {for (final i in items) if (on(i) && i.text('name').isNotEmpty) i.id: i};
  final liveCategories = {for (final c in categories) if (on(c)) c.id: c};

  // 1. One item: its name or one of its tags is exactly the label, or a table row points the label to it.
  final itemHits = <String, (double, String)>{};
  for (final l in sure) {
    final label = _phrase(l.text);
    for (final i in liveItems.values) {
      final names = [i.text('name'), ...i.text('tags').split(RegExp(r'[,;/]'))].map(_phrase).where((n) => n.isNotEmpty);
      if (names.contains(label)) itemHits.putIfAbsent(i.id, () => (l.confidence, l.text));
    }
    for (final r in rows) {
      if (r.itemId.isNotEmpty && liveItems.containsKey(r.itemId) && _rowFits(_phrase(r.label), label)) {
        itemHits.putIfAbsent(r.itemId, () => (l.confidence, l.text));
      }
    }
  }
  if (itemHits.length == 1) {
    final id = itemHits.keys.single;
    return CameraMatch.item(id, liveItems[id]!.text('name'), itemHits[id]!.$2);
  }

  // 2. A category: the table first, then a category's own name; the most sure labels together decide.
  final scores = <String, double>{};
  final firstLabel = <String, String>{};
  void add(String id, CameraLabel l) {
    if (!liveCategories.containsKey(id)) return;
    scores[id] = (scores[id] ?? 0) + l.confidence;
    firstLabel.putIfAbsent(id, () => l.text);
  }

  for (final l in sure) {
    final label = _phrase(l.text);
    final row = rows.where((r) => r.categoryId.isNotEmpty && _rowFits(_phrase(r.label), label)).firstOrNull;
    if (row != null) {
      add(row.categoryId, l);
      continue;
    }
    for (final c in liveCategories.values) {
      final parts = c.text('name').split(RegExp(r'[&,]')).map(_phrase).where((p) => p.isNotEmpty);
      if (parts.contains(label)) add(c.id, l);
    }
  }
  // Several items of one category (two kinds of onion): that category.
  if (scores.isEmpty && itemHits.length > 1) {
    final cats = {for (final id in itemHits.keys) liveItems[id]!.text('categoryId')}..remove('');
    if (cats.length == 1 && liveCategories.containsKey(cats.single)) return CameraMatch.category(cats.single, itemHits.values.first.$2);
  }
  if (scores.isEmpty) return const CameraMatch.none();
  final best = scores.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return CameraMatch.category(best, firstLabel[best]!);
}

/// The count key of one camera search: `label|what opened` (`item:name`, `category:id`, `chose:id`, `none`, `ai`).
String cameraUsageKey(String label, String opened) => '${label.trim().toLowerCase().isEmpty ? '-' : label.trim().toLowerCase()}|$opened';
