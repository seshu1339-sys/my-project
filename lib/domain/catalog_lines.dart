import 'catalog.dart';
import 'catalog_line_photos.dart';
import 'item_shops.dart';

// Category lines of the home page (owner, 16 Nov 2026): under Today's Offers, 2-3 lines, each line the items of ONE category with
// their photo, name and the lowest price in the customer's area ("Local vendor not updated item price" when no vendor there sells
// it), so the home page never looks empty in a place where vendors have not posted yet. After the admin's seconds a whole line fades
// to the next category; a category that comes back shows its NEXT items, going through all of them before starting again.
//
// Cost: nothing here reads Firestore. The items are the admin's Item Catalog (productImageLibrary) and the photos inside the app
// (catalog_line_photos.dart); the prices are the products; the settings are settings/androidHome: all of them are already loaded
// once when the app opens (Store.collections). The rotation runs on the phone only.

/// The part's name in the Android App order (Settings > Android App).
const catalogLinesPart = 'catalogLines';

/// What a box shows when no vendor in the customer's area has a price for the item (the owner's exact words).
const noLocalPriceText = 'Local vendor not updated item price';

/// The admin's choices (Settings > Android App > Category lines), in settings/androidHome. The app reads them when it opens.
class CatalogLinesConfig {
  const CatalogLinesConfig({this.seconds = defaultSeconds, this.lines = defaultLines, this.itemsApp = defaultItemsApp, this.itemsWeb = defaultItemsWeb, this.order = const []});

  static const defaultSeconds = 5, minSeconds = 3, maxSeconds = 30;
  static const defaultLines = 3, maxLines = 6;
  static const defaultItemsApp = 3, defaultItemsWeb = 6, minItems = 2, maxItems = 8;

  /// Seconds a line stays before it changes (3 to 30).
  final int seconds;
  /// Lines on the screen at once.
  final int lines;
  /// Items in a line: in the Android app, and on the website.
  final int itemsApp, itemsWeb;
  /// Category ids, first to last (1, 2, 3 ...); categories not in it come after, in the admin's category order.
  final List<String> order;

  int itemsPerLine({required bool android}) => android ? itemsApp : itemsWeb;

  factory CatalogLinesConfig.from(List<Entry> settings) {
    final doc = settings.where((e) => e.id == 'androidHome').firstOrNull;
    int read(String key, int fallback, int min, int max) {
      final v = doc?.number(key, 0).round() ?? 0;
      return v >= min && v <= max ? v : fallback;
    }
    return CatalogLinesConfig(
      seconds: read('lineSeconds', defaultSeconds, minSeconds, maxSeconds),
      lines: read('lineCount', defaultLines, 1, maxLines),
      itemsApp: read('lineItems', defaultItemsApp, minItems, maxItems),
      itemsWeb: read('lineItemsWeb', defaultItemsWeb, minItems, maxItems),
      order: [for (final id in (doc?.text('lineCategoryOrder') ?? '').split(',')) if (id.trim().isNotEmpty) id.trim()],
    );
  }

  Map<String, dynamic> toFields() => {
    'lineSeconds': seconds,
    'lineCount': lines,
    'lineItems': itemsApp,
    'lineItemsWeb': itemsWeb,
    'lineCategoryOrder': order.join(','),
  };
}

/// One box: an item of the admin's Item Catalog (a photo URL) or a photo inside the app (an asset).
class CatalogLineItem {
  const CatalogLineItem({required this.id, required this.name, required this.categoryId, this.asset = '', this.imageUrl = '', this.libraryItemId = ''});
  final String id, name, categoryId, asset, imageUrl, libraryItemId;
}

/// The items of each category: the admin's Item Catalog items (switched on, with a name, photo and category) first, then the app's
/// own photos of the categories with the same name. One item per name in a category (the catalog one wins).
Map<String, List<CatalogLineItem>> catalogLineItems({required List<Entry> categories, required List<Entry> library}) {
  final byName = {for (final c in categories) itemNameKey(c.text('name')): c.id};
  final ids = {for (final c in categories) c.id};
  final out = <String, List<CatalogLineItem>>{};
  final seen = <String, Set<String>>{};
  void add(CatalogLineItem item) {
    final key = itemNameKey(item.name);
    if (key.isEmpty || !(seen[item.categoryId] ??= {}).add(key)) return;
    (out[item.categoryId] ??= []).add(item);
  }
  for (final e in library) {
    final category = e.text('categoryId');
    if (!e.active || !ids.contains(category) || e.text('name').trim().isEmpty || e.text('imageUrl').isEmpty) continue;
    add(CatalogLineItem(id: e.id, name: e.text('name').trim(), categoryId: category, imageUrl: e.text('imageUrl'), libraryItemId: e.id));
  }
  for (final (asset, name, categoryName) in catalogLinePhotos) {
    final category = byName[itemNameKey(categoryName)];
    if (category == null) continue;
    add(CatalogLineItem(id: asset, name: name, categoryId: category, asset: asset));
  }
  return out;
}

/// The categories that have items, in the admin's line order, then the rest in the admin's category order.
List<String> catalogLineOrder(Map<String, List<CatalogLineItem>> items, List<Entry> categories, List<String> adminOrder) {
  final order = <String>[];
  for (final id in [...adminOrder, for (final c in categories) c.id]) {
    if ((items[id]?.isNotEmpty ?? false) && !order.contains(id)) order.add(id);
  }
  return order;
}

/// The lowest price of the item among the customer's products (the shops in their area): its product, price and unit.
class LinePrice {
  const LinePrice(this.product, this.price, this.unit);
  final Entry product;
  final double price;
  final String unit;
}

/// "2 kg" -> 2, "5 pcs" -> 5; anything else counts as one.
double _quantity(String unit) {
  final m = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(kg|pc|pcs)\b', caseSensitive: false).firstMatch(unit);
  final n = m == null ? 1.0 : double.parse(m.group(1)!);
  return n > 0 ? n : 1;
}

/// The cheapest offer of [item] in [products] (compared per kg or piece, so "₹70 for 2 kg" beats "₹40 for 1 kg"); null when none.
LinePrice? lowestLinePrice(CatalogLineItem item, List<Entry> products, {String pincode = ''}) {
  LinePrice? best;
  double bestEach = double.infinity;
  for (final p in products) {
    final price = p.price(pincode);
    if (price <= 0 || !isSameItem(p, name: item.name, libraryItemId: item.libraryItemId)) continue;
    final unit = p.text('unit');
    final each = price / _quantity(unit);
    if (each < bestEach) {
      bestEach = each;
      best = LinePrice(p, price, unit);
    }
  }
  return best;
}

/// What one line shows: a category and the positions of its items ([serial] changes with every change, for the fade).
class LineShow {
  const LineShow(this.categoryId, this.indexes, this.serial);
  final String categoryId;
  final List<int> indexes;
  final int serial;
}

/// The rotation of the lines, on the phone only. Each category keeps where its next set starts, so a category that comes back shows
/// its next items (all of them before starting again), never the set shown before; a line never has the same item twice, and two
/// lines on the screen never show the same category.
class CatalogLineRotation {
  CatalogLineRotation({required this.lines, required this.perLine});
  final int lines, perLine;
  List<String> _order = const [];
  Map<String, int> _counts = const {};
  final Map<String, int> _nextStart = {};
  int _queue = 0, _serial = 0;
  final List<LineShow> shown = [];

  /// The categories and how many items each has (again whenever the data changes; nothing is reset that still fits).
  void update(List<String> order, Map<String, int> counts) {
    final changed = order.join(',') != _order.join(',') || counts.toString() != _counts.toString();
    _order = order;
    _counts = counts;
    if (!changed && shown.isNotEmpty) return;
    shown.removeWhere((s) => !order.contains(s.categoryId) || s.indexes.any((i) => i >= (counts[s.categoryId] ?? 0)));
    while (shown.length > _lineCount) {
      shown.removeLast();
    }
    while (shown.length < _lineCount) {
      shown.add(_show(_pick(except: {for (final s in shown) s.categoryId})));
    }
  }

  int get _lineCount => _order.length < lines ? _order.length : lines;

  /// Line [line] fades to the next category (the same category's next items when every category is already on the screen).
  void next(int line) {
    if (line < 0 || line >= shown.length) return;
    final others = {for (var i = 0; i < shown.length; i++) if (i != line) shown[i].categoryId};
    final own = shown[line].categoryId;
    final pick = _pick(except: {...others, own}, fallback: own);
    shown[line] = _show(pick);
  }

  String _pick({required Set<String> except, String? fallback}) {
    for (var step = 0; step < _order.length; step++) {
      final id = _order[(_queue + step) % _order.length];
      if (!except.contains(id)) {
        _queue = (_queue + step + 1) % _order.length;
        return id;
      }
    }
    return fallback ?? _order.first;
  }

  LineShow _show(String category) {
    final n = _counts[category] ?? 0;
    final k = perLine < n ? perLine : n;
    final start = (_nextStart[category] ?? 0) % (n == 0 ? 1 : n);
    _nextStart[category] = n == 0 ? 0 : (start + k) % n;
    return LineShow(category, [for (var i = 0; i < k; i++) (start + i) % n], ++_serial);
  }
}
