import '../data/store.dart';
import '../domain/catalog.dart';
import 'home_section_config.dart';

// ---------------------------------------------------------------------------------------------
// "Today's Offers" (the banner with the town and the price chips, layout section `notice`) used to take everything it did not have of its own
// from the Scrolling Text record: its label, its border, its colours, its fonts. So changing the Scrolling Text changed that banner too.
//
// A banner is INDEPENDENT once its own record (section_notice) holds `independent: true`. From then on it reads only its own record. Until then
// it keeps the old behaviour so the live site does not change by itself; making it independent first copies what it was inheriting into its own
// record, so the banner looks exactly as before. (Settings > Today's Offers has the button; scripts/decouple-notice.cjs does the same.)
// ---------------------------------------------------------------------------------------------

/// The keys the banner reads from the Scrolling Text record when its own record has no value for them.
const noticeInheritedKeys = [
  'backgroundColor', 'backgroundImage', 'borderColor', 'borderWidth', 'brightness', 'gradientStart', 'gradientEnd', 'opacity', 'radius',
  'textColor', 'fontFamily', 'fontStyle', 'fontWeight', 'fontSize', 'text', 'translations',
];

bool noticeIsIndependent(List<Entry> settings) {
  final own = settings.where((e) => e.id == 'section_notice').firstOrNull;
  return own != null && (own.data['independent'] == true || own.text('independent') == 'true');
}

/// What the banner is inheriting right now: the keys of [scrollingText] it needs that its own record [notice] does not have.
Map<String, dynamic> noticeInherited(Entry? scrollingText, Entry? notice) => {
  if (scrollingText != null)
    for (final key in noticeInheritedKeys)
      if (scrollingText.data[key] != null && '${scrollingText.data[key]}'.isNotEmpty && !(notice?.data.containsKey(key) ?? false)) key: scrollingText.data[key],
};

/// Makes the banner independent: copies what it inherits into its own record and marks it. Returns how many values were copied (0 when it
/// was already independent). The banner looks the same before and after.
Future<int> makeNoticeIndependent(Store store) async {
  final settings = store.entries('settings');
  if (noticeIsIndependent(settings)) return 0;
  final scrolling = settings.where((e) => e.id == 'scrollingText').firstOrNull;
  final notice = sectionConfig(settings, 'notice');
  final copy = noticeInherited(scrolling, notice);
  await store.updateFields('settings', 'section_notice', {...copy, 'independent': true}, fallback: Entry('section_notice', {'section': 'notice', ...copy, 'independent': true}));
  return copy.length;
}
