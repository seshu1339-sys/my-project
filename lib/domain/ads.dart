import 'catalog.dart';
import 'home_animations.dart';
import 'radius.dart';
import 'towns.dart';

// ---------------------------------------------------------------------------------------------
// The unified Ads system. Every ad (added by the admin or approved from a vendor) is one record in the `ads` collection and is
// drawn by the same widget in the same box, so size, corners, animation and rules apply equally to all of them.
//
// Common settings (one record, `settings/adsConfig`) -> [AdsConfig]. Per-ad fields:
//   status         approved (default) | pending | rejected          active      false = switched off
//   contentType    image | text | imageText                          imageUrl, mobileImageUrl, title, text, textColor, backgroundColor
//   badge, coupon  tapAction call | whatsapp | shop | link          tapValue (number, shop id or address)
//   startsAt, endsAt (ISO)   days "1,2,3" (1 = Monday .. 7 = Sunday, blank = every day)   slots "09:00-12:00,18:00-21:00" (blank = all day)
//   locations (towns, blank = everywhere)   package normal|silver|gold   rounds, seconds, maxPerDay   pinned   order
// ---------------------------------------------------------------------------------------------

/// The change animations of the Right Side Ads: the one list shared by the whole home page (home_animations.dart).
const adAnimations = homeAnimations;

const adPackages = <String, String>{'normal': 'Normal', 'silver': 'Silver', 'gold': 'Gold'};

/// What a package fills in for "times per round", "seconds on screen" and "max times per day" (0 = no limit); all still editable.
const adPackageDefaults = <String, ({int rounds, int seconds, int maxPerDay})>{
  'normal': (rounds: 1, seconds: 5, maxPerDay: 0),
  'silver': (rounds: 2, seconds: 7, maxPerDay: 0),
  'gold': (rounds: 3, seconds: 10, maxPerDay: 0),
};

/// Settings that apply to ALL ads, from `settings/adsConfig`.
class AdsConfig {
  const AdsConfig({
    this.desktopSlots = 3,
    this.mobileSlots = 1,
    this.boxHeight = 240,
    this.fitToScreen = true,
    this.radius = 12,
    this.gap = 12,
    this.borderWidth = 0,
    this.borderColor = '#D32F2F',
    this.shadow = .15,
    this.animation = 'fade',
    this.animationSpeed = 5,
    this.seconds = 5,
    this.pauseOnHover = true,
    this.label = 'Ad',
    this.maxPerArea = 0,
    this.backgroundColor = '',
    this.textColor = '',
  });

  final int desktopSlots, mobileSlots;
  final double boxHeight, radius, gap, borderWidth, shadow;
  final bool fitToScreen, pauseOnHover;
  final String borderColor, animation, label;
  final int animationSpeed, seconds;
  // The most ads (or offers) with a radius that may run over the same area at the same time; 0 = no limit.
  final int maxPerArea;
  // Colours for ads that have none of their own ('' = the theme's).
  final String backgroundColor, textColor;

  /// How long one change takes, from speed 1 (slow) to 10 (fast).
  Duration get transition => Duration(milliseconds: (1400 - 110 * animationSpeed.clamp(1, 10)).round());

  factory AdsConfig.from(List<Entry> settings) {
    final doc = settings.where((e) => e.id == 'adsConfig').firstOrNull;
    if (doc == null) return const AdsConfig();
    const d = AdsConfig();
    int count(String key, int fallback) => doc.number(key, fallback.toDouble()).round().clamp(1, 12);
    final animation = doc.text('animation', d.animation);
    return AdsConfig(
      desktopSlots: count('desktopSlots', d.desktopSlots),
      mobileSlots: count('mobileSlots', d.mobileSlots),
      boxHeight: doc.number('boxHeight', d.boxHeight).clamp(80, 600).toDouble(),
      fitToScreen: doc.text('fitToScreen', 'true') != 'false',
      radius: doc.number('radius', d.radius).clamp(0, 60).toDouble(),
      gap: doc.number('gap', d.gap).clamp(0, 48).toDouble(),
      borderWidth: doc.number('borderWidth', d.borderWidth).clamp(0, 8).toDouble(),
      borderColor: doc.text('borderColor', d.borderColor),
      shadow: doc.number('shadow', d.shadow).clamp(0, 1).toDouble(),
      animation: animation == 'mix' || adAnimations.containsKey(animation) || legacyAnimations.containsKey(animation) ? animation : d.animation,
      animationSpeed: doc.number('animationSpeed', d.animationSpeed.toDouble()).round().clamp(1, 10),
      seconds: doc.number('seconds', d.seconds.toDouble()).round().clamp(2, 120),
      pauseOnHover: doc.text('pauseOnHover', 'true') != 'false',
      maxPerArea: doc.number('maxPerArea', 0).round().clamp(0, 50),
      backgroundColor: doc.text('backgroundColor'),
      textColor: doc.text('textColor'),
      label: doc.text('label', d.label).trim().isEmpty ? d.label : doc.text('label', d.label).trim(),
    );
  }
}

/// "1,2,5" -> {1, 2, 5}; blank or nothing valid -> every day.
Set<int> adDays(Entry ad) {
  final days = {
    for (final part in ad.text('days').split(RegExp(r'[,\s]+')))
      if (int.tryParse(part) case final n? when n >= 1 && n <= 7) n,
  };
  return days.isEmpty ? {1, 2, 3, 4, 5, 6, 7} : days;
}

/// "09:00-12:00, 18:00-21:00" -> minutes from midnight; blank = all day. A slot that ends before it starts runs past midnight.
List<(int, int)> adSlots(Entry ad) {
  final out = <(int, int)>[];
  for (final part in ad.text('slots').split(',')) {
    final match = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\s*$').firstMatch(part);
    if (match == null) continue;
    final from = int.parse(match[1]!) * 60 + int.parse(match[2]!);
    final to = int.parse(match[3]!) * 60 + int.parse(match[4]!);
    if (from < 24 * 60 && to <= 24 * 60) out.add((from, to));
  }
  return out;
}

bool _inSlots(List<(int, int)> slots, DateTime now) {
  if (slots.isEmpty) return true;
  final minute = now.hour * 60 + now.minute;
  return slots.any((s) => s.$1 <= s.$2 ? minute >= s.$1 && minute < s.$2 : minute >= s.$1 || minute < s.$2);
}

/// Where an ad is in its life, for the admin lists and filters: pending | rejected | inactive | expired | scheduled | live.
String adStatus(Entry ad, DateTime now) {
  final approval = ad.text('status', 'approved');
  if (approval == 'pending') return 'pending';
  if (approval == 'rejected') return 'rejected';
  if (!ad.active) return 'inactive';
  final start = DateTime.tryParse(ad.text('startsAt'));
  final end = DateTime.tryParse(ad.text('endsAt'));
  if (end != null && !now.isBefore(end)) return 'expired';
  if (start != null && now.isBefore(start)) return 'scheduled';
  return 'live';
}

/// Today's date in India (UTC+5:30), as YYYY-MM-DD: the day the daily limit counts in (the server uses the same day).
String adDay(DateTime now) => now.toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String().substring(0, 10);

/// True when the ad may be on a customer's screen at [now]: approved, switched on, inside its dates, its weekdays and its daily time slots.
bool adLiveNow(Entry ad, DateTime now) =>
    adStatus(ad, now) == 'live' &&
    adDays(ad).contains(now.weekday) &&
    _inSlots(adSlots(ad), now) &&
    // the server marks an ad that reached its "max times per day" with that day; it is hidden for the rest of it
    ad.text('capDay') != adDay(now);

/// The ads this customer can see now, pinned first, then in the admin's order. Location uses the same rule as offers: ads that list the
/// customer's town (else the general, all-town ones).
List<Entry> liveAds(
  List<Entry> ads,
  DateTime now, {
  String town = '',
  String district = '',
  String state = '',
  bool showAll = false,
  double? latitude,
  double? longitude,
}) {
  // Only ads whose circle covers the customer's current location, each ad once; the admin's preview ([showAll]) shows every live ad.
  final running = ads.where((a) => adLiveNow(a, now)).toList();
  final live = showAll ? running : coveringCustomer(running, latitude, longitude);
  final local = promotionsForTown(live, town, district: district, state: state, showAll: showAll).entries.toList();
  local.sort((a, b) {
    final pin = (b.text('pinned') == 'true' || b.data['pinned'] == true ? 1 : 0) - (a.text('pinned') == 'true' || a.data['pinned'] == true ? 1 : 0);
    return pin != 0 ? pin : a.number('order').compareTo(b.number('order'));
  });
  return local;
}

/// Seconds an ad stays on screen each time (its own, else the common default).
int adSeconds(Entry ad, AdsConfig config) => ad.number('seconds') > 0 ? ad.number('seconds').round().clamp(2, 120) : config.seconds;

/// How many times an ad appears in one round of the rotation (1x, 2x, 3x).
int adRounds(Entry ad) => ad.number('rounds') >= 1 ? ad.number('rounds').round().clamp(1, 3) : 1;

/// One full round of the rotation: every ad once, then the ads that want 2x or 3x again, so the same ad is not shown twice in a row.
List<Entry> adCycle(List<Entry> live) {
  final cycle = <Entry>[];
  for (var round = 1; round <= 3; round++) {
    cycle.addAll(live.where((a) => adRounds(a) >= round));
  }
  return cycle;
}

/// What tapping an ad does, as the address the storefront already understands: tel:..., https://wa.me/..., shop:ID or a web link.
String adTarget(Entry ad) {
  final value = ad.text('tapValue').trim();
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  final full = digits.length == 10 ? '91$digits' : digits;
  switch (ad.text('tapAction')) {
    case 'call':
      return digits.isEmpty ? '' : 'tel:+$full';
    case 'whatsapp':
      return digits.isEmpty ? '' : 'https://wa.me/$full';
    case 'shop':
      return value.isEmpty ? '' : 'shop:$value';
    case 'link':
      return value;
  }
  return ad.text('target');
}
