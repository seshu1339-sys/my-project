import 'ads.dart';
import 'catalog.dart';

/// Where things go on the home screen of the Android app. The website never reads this: it keeps reading its own settings
/// (settings/adsConfig, section_*, layout), so a change here cannot move anything on the website. Only the placement is separate;
/// the ads, offers and every other record are the same ones the website shows.
///
/// Stored in `settings/androidHome`:
///   adSlots   how many ad boxes show at once (blank = the older "Ad boxes on a phone" value of Right Side Ads)
///   order     the parts, top to bottom, "scrollingText,notice,promo,ads,boxes" (blank or missing parts = the default order)
///   hidden    the parts that are not shown, "boxes,notice" (blank = all shown)
/// How long each ad stays (the slide time) is not here: the app reads the same `seconds` setting of Right Side Ads as the website.
const androidHomeId = 'androidHome';

/// The parts of the home screen the admin can place, in the order the app starts with.
const androidHomeParts = ['scrollingText', 'notice', 'promo', 'ads', 'boxes'];

class AndroidHomeConfig {
  const AndroidHomeConfig({required this.adSlots, required this.order, required this.hidden});

  final int adSlots;
  final List<String> order;
  final Set<String> hidden;

  bool shows(String part) => !hidden.contains(part);

  /// The parts to build, top to bottom: the chosen order, hidden ones left out.
  List<String> get visibleParts => [for (final p in order) if (shows(p)) p];

  factory AndroidHomeConfig.from(List<Entry> settings) {
    final doc = settings.where((e) => e.id == androidHomeId).firstOrNull;
    final ads = AdsConfig.from(settings);
    List<String> csv(String key) => [for (final p in (doc?.text(key) ?? '').split(',')) if (androidHomeParts.contains(p.trim())) p.trim()];
    final chosen = csv('order').toSet().toList();
    final slots = doc?.number('adSlots', 0).round() ?? 0;
    return AndroidHomeConfig(
      adSlots: slots >= 1 ? slots.clamp(1, 12) : ads.mobileSlots,
      // parts missing from the saved order go after the chosen ones, in the default order
      order: [...chosen, for (final p in androidHomeParts) if (!chosen.contains(p)) p],
      hidden: csv('hidden').toSet(),
    );
  }

  /// The fields to save for this choice (all text, like the other settings records).
  Map<String, dynamic> toFields() => {'adSlots': adSlots, 'order': order.join(','), 'hidden': androidHomeParts.where(hidden.contains).join(',')};
}
