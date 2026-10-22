import '../domain/catalog.dart';
import 'home_section_config.dart';
import 'section_animations.dart';

// ---------------------------------------------------------------------------------------------
// Settings -> Animations: one record (`settings/animations`) that switches the website's animations on or off, as a whole and
// for each part of the page, and sets their type and speed. It layers on top of what each part already has in its own layout
// settings: with no `animations` record (or one with nothing set) the site looks exactly as it always did.
//
//   enabled            'false' turns every animation off.        defaultType / defaultSpeed: for parts that have none of their own
//   <part>_enabled     'false' turns that part's animations off.   <part>_type   none | fade | slide | zoom
//   <part>_speed       1 (slow) .. 10 (fast)                      <part>_rotation  how a rotating banner/ad changes (promo, ads)
// ---------------------------------------------------------------------------------------------

/// The parts of the page that can animate, in the order the page shows them: layout key -> label.
const animationParts = <String, String>{
  'scrollingText': 'Scrolling Text',
  'header': 'Header',
  'notice': 'Today\'s Offers',
  'promo': 'Today\'s Offers Box',
  'boxes': 'Right Side Ads: boxes below the ads',
  'categories': 'Categories',
  'popular': 'Popular Products',
  'localServices': 'Local Services',
  'crossSellStrip': 'Fresh Fruits & Vegetables strip',
  'ads': 'Right Side Ads',
  'nearby': 'Nearby shops',
  'background': 'Page background',
};

/// Parts whose pictures rotate on their own; they also get a "how it changes" choice.
const rotatingParts = {'promo', 'ads'};

/// Every animation the admin can choose (one list for the whole home page, see section_animations.dart).
const entranceTypes = homeAnimations;

/// How long one entrance takes for a speed from 1 (slow) to 10 (fast), in milliseconds. Unset keeps the original 450 ms.
int entranceMillis(int speed) => (1400 - 110 * speed.clamp(1, 10)).round();

const entranceMillisDefault = 450;

Entry animationsDoc(List<Entry> settings) => settings.firstWhere((e) => e.id == 'animations', orElse: () => const Entry('animations', {}));

bool animationsEnabled(List<Entry> settings) => animationsDoc(settings).text('enabled', 'true') != 'false';

int? _speedOf(Entry doc, String key) {
  final value = doc.data[key];
  final n = value is num ? value.toInt() : int.tryParse('$value');
  return n != null && n >= 1 && n <= 10 ? n : null;
}

/// The settings of one part of the page as the WEBSITE should use them: its own layout settings with the Animations record
/// applied on top (switched off, a different type, a speed). The admin's forms keep reading [sectionConfig], which is the raw
/// record, so a value that only comes from the Animations section is never saved back into a part's own settings.
Entry effectiveSectionConfig(List<Entry> settings, String section) {
  final raw = sectionConfig(settings, section);
  final doc = animationsDoc(settings);
  // With nothing chosen in Settings > Animations the site is unchanged, except that the four home sections start with their own simple animation.
  if (doc.data.isEmpty && !homeSectionDefaults.containsKey(section)) return raw;
  final data = {...raw.data};
  final off = doc.text('enabled', 'true') == 'false' || doc.text('${section}_enabled', 'true') == 'false';
  if (off) {
    data['animation'] = 'none';
    for (final key in ['animationType', 'textAnimation', 'headingAnimation']) {
      data.remove(key);
    }
    return Entry(raw.id, data);
  }
  // type: this part's choice here, else what it already has in its own settings, else the default for all
  final own = doc.text('${section}_type');
  final inherited = raw.text('animation');
  final fallback = doc.text('defaultType');
  final type = own.isNotEmpty ? own : (inherited.isNotEmpty ? inherited : (fallback.isNotEmpty ? fallback : (homeSectionDefaults[section] ?? '')));
  if (type.isNotEmpty && entranceTypes.containsKey(type)) data['animation'] = type;
  final speed = _speedOf(doc, '${section}_speed') ?? _speedOf(doc, 'defaultSpeed');
  if (speed != null) {
    data['entranceMs'] = entranceMillis(speed);
    data['animationSpeed'] = speed; // the same speed for a rotating banner/ad
  }
  final rotation = doc.text('${section}_rotation');
  if (rotatingParts.contains(section) && rotation.isNotEmpty) data['animationType'] = rotation;
  return Entry(raw.id, data);
}
