import 'catalog.dart';

/// The numbers the ad reports add up. All come from what the server counted (functions/ad-tracking.js); nothing is estimated here.
class AdTotals {
  AdTotals({this.views = 0, this.unique = 0, this.taps = 0, this.seconds = 0, this.missed = 0});
  int views, unique, taps, seconds, missed;

  void add(Map<String, dynamic> data, {bool withUnique = true}) {
    int n(String k) => (data[k] is num) ? (data[k] as num).round() : 0;
    views += n('views');
    taps += n('taps');
    seconds += n('seconds');
    missed += n('missed');
    if (withUnique) unique += n('unique');
  }

  /// Times the ad was due on screen: seen, or not seen.
  int get scheduled => views + missed;
}

/// A town key as stored (narsipatnam_east) in words.
String townLabel(String key) => key.split('_').where((w) => w.isNotEmpty).map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

/// The per-day ad statistics added up for a date range, with the filters the admin chooses.
class AdReport {
  AdReport._(this.total, this.byDay, this.byAd, this.byTown, this.byDevice, {required this.uniqueKnown});
  final AdTotals total;
  final Map<String, AdTotals> byDay, byAd, byTown, byDevice;
  // "Unique people" is counted per ad, not per town or device, so it is only shown when no town or device filter is on.
  final bool uniqueKnown;

  /// [daily] are `adStatsDaily` records. [adIds] limits to those ads (null = all). [town] (a town key) or [device] (web / android) limits
  /// the numbers to that part of the traffic.
  factory AdReport.build(List<Entry> daily, {Set<String>? adIds, String? town, String? device}) {
    final total = AdTotals();
    final byDay = <String, AdTotals>{}, byAd = <String, AdTotals>{}, byTown = <String, AdTotals>{}, byDevice = <String, AdTotals>{};
    final narrowed = town != null || device != null;
    for (final doc in daily) {
      final adId = doc.text('adId');
      if (adIds != null && !adIds.contains(adId)) continue;
      Map<String, dynamic> pick() {
        if (town != null) return Map<String, dynamic>.from((doc.data['towns'] as Map?)?[town] as Map? ?? const {});
        if (device != null) return Map<String, dynamic>.from((doc.data['devices'] as Map?)?[device] as Map? ?? const {});
        return doc.data;
      }

      final data = pick();
      total.add(data, withUnique: !narrowed);
      byDay.putIfAbsent(doc.text('day'), AdTotals.new).add(data, withUnique: !narrowed);
      byAd.putIfAbsent(adId, AdTotals.new).add(data, withUnique: !narrowed);
      for (final e in ((doc.data['towns'] as Map?) ?? const {}).entries) {
        byTown.putIfAbsent('${e.key}', AdTotals.new).add(Map<String, dynamic>.from(e.value as Map), withUnique: false);
      }
      for (final e in ((doc.data['devices'] as Map?) ?? const {}).entries) {
        byDevice.putIfAbsent('${e.key}', AdTotals.new).add(Map<String, dynamic>.from(e.value as Map), withUnique: false);
      }
    }
    return AdReport._(total, byDay, byAd, byTown, byDevice, uniqueKnown: !narrowed);
  }

  /// The days from [from] to [to] (inclusive, YYYY-MM-DD), in order, with zeros for days that have no numbers: the graph's x axis.
  List<(String, AdTotals)> days(String from, String to) {
    final out = <(String, AdTotals)>[];
    var d = DateTime.parse(from);
    final end = DateTime.parse(to);
    while (!d.isAfter(end) && out.length < 400) {
      final key = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      out.add((key, byDay[key] ?? AdTotals()));
      d = d.add(const Duration(days: 1));
    }
    return out;
  }
}

/// A plain-text summary, for sharing (WhatsApp) and for the top of an export.
String reportSummaryText(AdReport report, {required String from, required String to, String? title}) {
  final t = report.total;
  return [
    '${title ?? 'Ads report'}  $from to $to',
    'Total views: ${t.views}',
    if (report.uniqueKnown) 'Unique people: ${t.unique}',
    'Taps: ${t.taps}',
    'Time on screen: ${t.seconds} s',
    'Scheduled but missed: ${t.missed}',
  ].join('\n');
}
