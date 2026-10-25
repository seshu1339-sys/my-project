import 'catalog.dart';

// The admin's Analytics reports, added up from the daily usage counts (functions/usage.js):
//   usageDaily/<day>~<event>       {day, event, total, keys: {<k>: {key, label, town, count}}}
//   usagePersonDaily/<uid>~<day>   {uid, day, counts: {<event>: n}, keys: {<event~k>: {event, key, label, count}}}

/// What each event means, for the admin.
const usageEventLabels = {
  'shop_call': 'Calls to shops',
  'shop_whatsapp': 'WhatsApp to shops',
  'shop_directions': 'Directions to shops',
  'worker_call': 'Calls to service workers',
  'worker_whatsapp': 'WhatsApp to service workers',
  'map_view': 'Map opened (after choosing an item)',
  'price_list_view': 'Price list seen (lowest price first)',
  'service_open': 'Services opened',
  'search': 'Searches',
  'search_no_result': 'Searches with no result',
  'location_change': 'Towns chosen',
  'offer_click': 'Offer boxes tapped',
  'transport_click': 'Transport tapped (coming soon)',
  'screen_view': 'Screens opened',
  'button': 'Buttons used',
  'notification_open': 'Notifications opened',
  'vendor_register': 'Vendor registrations',
  'item_added': 'Items added by vendors',
  'price_changed': 'Price changes',
  'ad_interest': '"Ad for your shop" ticks',
  'staff_added': 'Added by staff',
};

class UsageKeyRow {
  UsageKeyRow(this.key, this.label, this.town, this.count);
  final String key, label, town;
  int count;
}

int _n(Object? v) => v is num ? v.round() : 0;

/// The usage of a date range, from usageDaily records.
class UsageReport {
  UsageReport._(this._totals, this._keys, this._days);
  final Map<String, int> _totals;
  final Map<String, Map<String, UsageKeyRow>> _keys;
  final Map<String, Map<String, int>> _days;

  factory UsageReport.build(Iterable<Entry> daily) {
    final totals = <String, int>{}, keys = <String, Map<String, UsageKeyRow>>{}, days = <String, Map<String, int>>{};
    for (final doc in daily) {
      final event = doc.text('event'), day = doc.text('day');
      if (event.isEmpty) continue;
      totals[event] = (totals[event] ?? 0) + _n(doc.data['total']);
      (days[event] ??= {})[day] = (days[event]![day] ?? 0) + _n(doc.data['total']);
      final rows = keys[event] ??= {};
      for (final entry in ((doc.data['keys'] as Map?) ?? const {}).values) {
        if (entry is! Map) continue;
        final key = '${entry['key'] ?? ''}';
        final row = rows[key] ??= UsageKeyRow(key, '${entry['label'] ?? ''}', '${entry['town'] ?? ''}', 0);
        row.count += _n(entry['count']);
      }
    }
    return UsageReport._(totals, keys, days);
  }

  int total(String event) => _totals[event] ?? 0;

  /// What [event] was about, the most first.
  List<UsageKeyRow> top(String event, {int max = 100}) {
    final rows = [...?_keys[event]?.values]..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.label.compareTo(b.label));
    return rows.take(max).toList();
  }

  /// [event] per day (YYYY-MM-DD).
  Map<String, int> byDay(String event) => Map.unmodifiable(_days[event] ?? const {});

  /// One row per key across several events (a shop's calls, WhatsApp and directions), the most in all first.
  List<({String key, String label, String town, Map<String, int> counts, int total})> merged(List<String> events, {int max = 200}) {
    final rows = <String, ({String key, String label, String town, Map<String, int> counts})>{};
    for (final event in events) {
      for (final r in _keys[event]?.values ?? const <UsageKeyRow>[]) {
        final row = rows[r.key] ??= (key: r.key, label: r.label, town: r.town, counts: <String, int>{});
        row.counts[event] = (row.counts[event] ?? 0) + r.count;
      }
    }
    final out = [for (final r in rows.values) (key: r.key, label: r.label, town: r.town, counts: r.counts, total: r.counts.values.fold(0, (a, b) => a + b))];
    out.sort((a, b) => b.total.compareTo(a.total));
    return out.take(max).toList();
  }
}

/// One signed-in person's usage over a range, from their usagePersonDaily records.
class PersonUsage {
  PersonUsage(this.uid);
  final String uid;
  final counts = <String, int>{};
  final keys = <String, UsageKeyRow>{};
  final days = <String>{};
  int get total => counts.values.fold(0, (a, b) => a + b);

  /// Everyone in [docs], the most active first.
  static List<PersonUsage> build(Iterable<Entry> docs) {
    final people = <String, PersonUsage>{};
    for (final doc in docs) {
      final uid = doc.text('uid');
      if (uid.isEmpty) continue;
      final person = people[uid] ??= PersonUsage(uid);
      person.days.add(doc.text('day'));
      ((doc.data['counts'] as Map?) ?? const {}).forEach((event, n) => person.counts['$event'] = (person.counts['$event'] ?? 0) + _n(n));
      ((doc.data['keys'] as Map?) ?? const {}).forEach((k, v) {
        if (v is! Map) return;
        final row = person.keys['$k'] ??= UsageKeyRow('${v['key'] ?? ''}', '${v['event'] ?? ''}: ${v['label'] ?? v['key'] ?? ''}', '', 0);
        row.count += _n(v['count']);
      });
    }
    return people.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  }
}

/// The days from [from] to [to] (YYYY-MM-DD, India) as text, for the queries.
String usageDay(DateTime d) {
  final india = d.toUtc().add(const Duration(hours: 5, minutes: 30));
  return '${india.year.toString().padLeft(4, '0')}-${india.month.toString().padLeft(2, '0')}-${india.day.toString().padLeft(2, '0')}';
}
