import 'catalog.dart';

/// The sizes of the Android app's home screen, apart from the website's. The website never reads this record; it keeps its own sizes in
/// Settings > Layout. The app lays these values over the website's records (see [AndroidSizes.applyTo]), so every home widget reads
/// them through the same `layoutFor` as before.
///
/// Stored in `settings/androidSizes`:
///   part__field       a size of one part, for example notice__fontSize (blank = see below)
///   separate          "true" once "Copy website sizes to Android" has been used: from then on the app ignores the website's sizes
///                     altogether, and a blank field means the part's normal size. Until then a blank field follows the website.
const androidSizesId = 'androidSizes';

/// The side margin of the Android home page until the admin chooses another.
const androidDefaultEdge = 6.0;

/// What the top row does to the search box until the admin chooses otherwise (lib/ui/android_home_header.dart).
const androidSearchDefaults = <String, double>{'height': 44, 'margin': 0, 'padding': 0};

class AndroidSizeField {
  const AndroidSizeField(this.id, this.label, this.min, this.max, {this.recordKeys = const []});
  final String id, label;
  final double min, max;
  // The fields of the website's record it replaces, when they are not simply [id].
  final List<String> recordKeys;

  List<String> get keys => recordKeys.isEmpty ? [id] : recordKeys;
}

class AndroidSizePart {
  const AndroidSizePart(this.id, this.title, this.recordId, this.fields);
  final String id, title;
  // The website record these sizes replace; '' when the part exists only in the app.
  final String recordId;
  final List<AndroidSizeField> fields;
}

const _scale = AndroidSizeField('scale', 'Scale (0.75 to 1.5)', .75, 1.5, recordKeys: ['mobileScale', 'tabletScale', 'desktopScale']);
const _columns = AndroidSizeField('columns', 'Items in a row (1 to 3)', 1, 3, recordKeys: ['mobileColumns', 'tabletColumns', 'desktopColumns', 'columns']);
const _padding = AndroidSizeField('padding', 'Padding (inside)', 0, 48);
const _margin = AndroidSizeField('margin', 'Margin (outside)', 0, 48);
const _font = AndroidSizeField('fontSize', 'Font size', 10, 40);
const _border = AndroidSizeField('borderWidth', 'Border width', 0, 16);
const _gap = AndroidSizeField('gap', 'Gap between items', 0, 64);

/// Every part with sizes, top to bottom, and only the fields that part really reads.
const androidSizeParts = [
  AndroidSizePart('page', 'Whole page', '', [AndroidSizeField('padding', 'Side margin', 0, 24)]),
  AndroidSizePart('search', 'Search box', 'section_search', [_scale, AndroidSizeField('height', 'Height (the box stays at least 48 high)', 30, 120), _font, _padding, _margin, _border]),
  AndroidSizePart('ads', 'Ad boxes', '', [AndroidSizeField('height', 'Height of an ad box', 40, 300)]),
  AndroidSizePart('scrollingText', 'Scrolling Text', 'scrollingText', [AndroidSizeField('height', 'Height', 24, 120), _font, AndroidSizeField('padding', 'Padding (inside)', 0, 40), _border]),
  AndroidSizePart('notice', "Today's Offers banner", 'section_notice', [AndroidSizeField('height', 'Height', 0, 300), _font, _padding, _margin, _border]),
  AndroidSizePart('promo', "Today's Offers cards", 'section_promo', [_scale, AndroidSizeField('height', 'Card height (120 minimum)', 120, 600), _gap, _padding, _margin]),
  AndroidSizePart('crossSellStrip', 'Fresh Fruits & Vegetables', 'section_crossSellStrip', [AndroidSizeField('imageHeight', 'Photo height (never smaller than the card needs)', 32, 400)]),
  AndroidSizePart('popular', 'Products section', 'section_popular', [_padding, _margin]),
  AndroidSizePart('products', 'Product cards', 'section_products', [_columns, AndroidSizeField('height', 'Card height', 0, 800), _gap, _font]),
  AndroidSizePart('localServices', 'Local Services', 'section_localServices', [_columns, _padding, _margin]),
  AndroidSizePart('nearby', 'Shops section', 'section_nearby', [AndroidSizeField('height', 'Map height (180 minimum)', 180, 800), _padding, _margin]),
  AndroidSizePart('nearbyShopCard', 'Shop cards', 'section_nearbyShopCard', [AndroidSizeField('padding', 'Padding (inside)', 0, 48), AndroidSizeField('iconSize', 'Icon size', 16, 48)]),
];

class AndroidSizes {
  const AndroidSizes(this.values, {this.separate = false});

  /// Saved sizes by `<part>__<field>`.
  final Map<String, double> values;
  final bool separate;

  static String key(String part, String field) => '${part}__$field';

  double? value(String part, String field) => values[key(part, field)];

  factory AndroidSizes.from(List<Entry> settings) {
    final doc = settings.where((e) => e.id == androidSizesId).firstOrNull;
    if (doc == null) return const AndroidSizes({});
    final values = <String, double>{};
    for (final part in androidSizeParts) {
      for (final field in part.fields) {
        final k = key(part.id, field.id);
        if (!doc.data.containsKey(k)) continue;
        final v = double.tryParse('${doc.data[k]}');
        if (v != null && v.isFinite) values[k] = v.clamp(field.min, field.max).toDouble();
      }
    }
    return AndroidSizes(values, separate: doc.text('separate') == 'true');
  }

  /// [record] as the Android app should read it: this app's sizes in place of the website's.
  Entry entry(Entry record) {
    final part = androidSizeParts.where((p) => p.recordId == record.id).firstOrNull;
    if (part == null) return record;
    final data = {...record.data};
    for (final field in part.fields) {
      final v = value(part.id, field.id);
      for (final k in field.keys) {
        if (v != null) {
          data[k] = v;
        } else if (separate) {
          data.remove(k);
        }
      }
    }
    return Entry(record.id, data);
  }

  /// The settings as the Android app should read them. Nothing is saved.
  List<Entry> applyTo(List<Entry> settings) {
    if (values.isEmpty && !separate) return settings;
    return [
      for (final e in settings) entry(e),
      // a part the website has no record for yet
      for (final part in androidSizeParts)
        if (part.recordId.isNotEmpty && !settings.any((e) => e.id == part.recordId)) entry(Entry(part.recordId, const {})),
    ];
  }

  /// What the website's record has for [field], or null.
  static double? websiteValue(List<Entry> settings, AndroidSizePart part, AndroidSizeField field) {
    final record = settings.where((e) => e.id == part.recordId).firstOrNull;
    if (record == null) return null;
    for (final k in field.keys) {
      // A phone reads only the mobile value (or the plain one), so a desktop scale of 1.5 says nothing about the app.
      if (k.startsWith('tablet') || k.startsWith('desktop')) continue;
      if (record.data.containsKey(k)) {
        final v = double.tryParse('${record.data[k]}');
        if (v != null && v.isFinite) return v;
      }
    }
    return null;
  }

  /// The record "Copy website sizes to Android" saves: the sizes the app shows now, marked separate, so the app looks the same but no
  /// longer follows the website. A size the website has not set stays blank (the part's normal size).
  static Map<String, dynamic> copiedFields(List<Entry> settings) {
    final fields = <String, dynamic>{
      'name': 'Android app sizes',
      'separate': 'true',
      key('page', 'padding'): androidDefaultEdge,
    };
    for (final part in androidSizeParts) {
      for (final field in part.fields) {
        final fixed = part.id == 'search' ? androidSearchDefaults[field.id] : null;
        final v = fixed ?? websiteValue(settings, part, field);
        if (v != null) fields[key(part.id, field.id)] = v.clamp(field.min, field.max).toDouble();
      }
    }
    return fields;
  }
}
