import 'catalog.dart';

/// Where things go on the home screen of the Android app. The website never reads this: it keeps reading its own settings
/// (settings/adsConfig, section_*, layout), so a change here cannot move anything on the website. Only the placement is separate;
/// the ads, offers and every other record are the same ones the website shows.
///
/// Stored in `settings/androidHome`:
///   adSlots   how many ad boxes show at once (blank = 2)
///   showAds   "false" hides the ad boxes in the app (blank = shown)
///   order     the parts, top to bottom, "ads,scrollingText,notice,..." (blank = the usual order)
///   hidden    the parts that are not shown, "nearby,quickFresh" (blank = all shown; the ad boxes use showAds)
/// How long each ad stays (the slide time) is not here: the app reads the same `seconds` setting of Right Side Ads as the website.
const androidHomeId = 'androidHome';

/// Ad boxes side by side on the Android home screen until the admin chooses another number.
const defaultAndroidAdSlots = 2;

/// The parts of the Android home screen under the top row (logo, location, search, menu).
const androidHomeParts = ['ads', 'scrollingText', 'notice', 'quickFresh', 'promo', 'strip', 'popular', 'localServices', 'nearby'];

class AndroidHomeConfig {
  const AndroidHomeConfig({required this.adSlots, this.showAds = true, this.order = const [], this.hidden = const {}});

  final int adSlots;
  final bool showAds;

  /// The saved order (parts the admin placed); empty until the admin saves one.
  final List<String> order;

  /// The saved hidden parts (never contains 'ads': that is [showAds]).
  final Set<String> hidden;

  bool shows(String part) => part == 'ads' ? showAds : !hidden.contains(part);

  /// [defaults] (the usual top-to-bottom order) with the saved order applied: placed parts first in the saved order, any part the
  /// admin has not placed after them in its usual place. Unknown names are dropped.
  List<String> arrange(List<String> defaults) {
    final placed = <String>[];
    for (final p in order) {
      if (defaults.contains(p) && !placed.contains(p)) placed.add(p);
    }
    return [...placed, for (final p in defaults) if (!placed.contains(p)) p];
  }

  /// The parts to build, top to bottom: [arrange]d, hidden ones left out.
  List<String> visibleOrder(List<String> defaults) => [for (final p in arrange(defaults)) if (shows(p)) p];

  factory AndroidHomeConfig.from(List<Entry> settings) {
    final doc = settings.where((e) => e.id == androidHomeId).firstOrNull;
    final slots = doc?.number('adSlots', 0).round() ?? 0;
    List<String> csv(String key) => [for (final p in (doc?.text(key) ?? '').split(',')) if (androidHomeParts.contains(p.trim())) p.trim()];
    return AndroidHomeConfig(
      adSlots: slots >= 1 ? slots.clamp(1, 12) : defaultAndroidAdSlots,
      showAds: doc == null || (doc.data['showAds'] != false && doc.text('showAds') != 'false'),
      order: csv('order'),
      hidden: csv('hidden').where((p) => p != 'ads').toSet(),
    );
  }

  /// The fields to save for this choice.
  Map<String, dynamic> toFields() => {
    'adSlots': adSlots,
    'showAds': showAds ? 'true' : 'false',
    'order': order.join(','),
    'hidden': androidHomeParts.where(hidden.contains).join(','),
  };
}
