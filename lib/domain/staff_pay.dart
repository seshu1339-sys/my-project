// Staff targets and pay, the same rules as functions/modules/staff-work/rules.js (owner, 13 Nov 2026): a daily target (50 updates
// unless the admin sets one), a monthly target (daily x the days of the month unless set), the admin's pay slabs [{percent, amount}];
// the month's pay is the amount of the highest slab reached. Only worked out here: nobody is paid by the app.
const defaultDailyTarget = 50;

String istDay(DateTime t) => t.toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String().substring(0, 10);
String istMonth(DateTime t) => istDay(t).substring(0, 7);

int daysInMonth(String month) {
  final parts = month.split('-');
  return DateTime.utc(int.parse(parts[0]), int.parse(parts[1]) + 1, 0).day;
}

typedef PaySlab = ({num percent, num amount});
typedef StaffTargets = ({int daily, int monthly, List<PaySlab> slabs});

List<PaySlab> slabsOf(Object? list) => [
  for (final s in (list is List ? list : const []))
    if (s is Map && s['percent'] is num && s['amount'] is num) (percent: s['percent'] as num, amount: s['amount'] as num),
]..sort((a, b) => a.percent.compareTo(b.percent));

int? _whole(Object? v) => v is num && v >= 1 ? v.round() : null;

/// The targets of one staff member for a month: their own numbers ([own], staffPayTargets) where set, else everyone's ([config]).
StaffTargets targetsFor(Map<String, dynamic>? config, Map<String, dynamic>? own, String month) {
  final daily = _whole(own?['dailyTarget']) ?? _whole(config?['dailyTarget']) ?? defaultDailyTarget;
  final monthly = _whole(own?['monthlyTarget']) ?? _whole(config?['monthlyTarget']) ?? daily * daysInMonth(month);
  final slabs = own?['slabs'] is List ? slabsOf(own!['slabs']) : slabsOf(config?['slabs']);
  return (daily: daily, monthly: monthly, slabs: slabs);
}

typedef StaffPay = ({num percent, PaySlab? slab, num amount, PaySlab? next});

/// What [updates] of the month earn with these targets.
StaffPay payFor(int updates, StaffTargets t) {
  final percent = t.monthly > 0 ? (updates / t.monthly * 1000).round() / 10 : 0;
  PaySlab? reached;
  PaySlab? next;
  for (final s in t.slabs) {
    if (s.percent <= percent) {
      reached = s;
    } else {
      next ??= s;
    }
  }
  return (percent: percent, slab: reached, amount: reached?.amount ?? 0, next: next);
}

/// Daily counts grouped by week (Monday first) or month, for the graphs: [(label, value)] in time order.
List<(String, int)> groupCounts(List<(String, int)> days, String by) {
  if (by == 'day') return days;
  final out = <String, int>{};
  for (final (day, n) in days) {
    final d = DateTime.parse(day);
    final key = by == 'month' ? day.substring(0, 7) : istDay(d.subtract(Duration(days: d.weekday - 1))).substring(5);
    out[key] = (out[key] ?? 0) + n;
  }
  return [for (final e in out.entries) (e.key, e.value)];
}
