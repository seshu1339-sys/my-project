import 'catalog.dart';

/// Where things go on the home screen of the Android app. The website never reads this: it keeps reading its own settings
/// (settings/adsConfig, section_*, layout), so a change here cannot move anything on the website. Only the placement is separate;
/// the ads, offers and every other record are the same ones the website shows.
///
/// Stored in `settings/androidHome`:
///   adSlots   how many ad boxes show at once (blank = 2)
///   showAds   "false" hides the ad boxes in the app (blank = shown)
/// How long each ad stays (the slide time) is not here: the app reads the same `seconds` setting of Right Side Ads as the website.
const androidHomeId = 'androidHome';

/// Ad boxes side by side on the Android home screen until the admin chooses another number.
const defaultAndroidAdSlots = 2;

class AndroidHomeConfig {
  const AndroidHomeConfig({required this.adSlots, this.showAds = true});

  final int adSlots;
  final bool showAds;

  factory AndroidHomeConfig.from(List<Entry> settings) {
    final doc = settings.where((e) => e.id == androidHomeId).firstOrNull;
    final slots = doc?.number('adSlots', 0).round() ?? 0;
    return AndroidHomeConfig(
      adSlots: slots >= 1 ? slots.clamp(1, 12) : defaultAndroidAdSlots,
      showAds: doc == null || (doc.data['showAds'] != false && doc.text('showAds') != 'false'),
    );
  }

  /// The fields to save for this choice.
  Map<String, dynamic> toFields() => {'adSlots': adSlots, 'showAds': showAds ? 'true' : 'false'};
}
