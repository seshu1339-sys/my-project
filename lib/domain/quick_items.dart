import 'catalog.dart';

/// Quick Add Item: the rules the screens share (they mirror functions/quick-domain.js, which is
/// what the server actually enforces).
const quickUnits = <String>[
  'per kg',
  'per piece',
  'per dozen',
  'per litre',
  'per bundle',
  'per packet',
  'per 500 g',
  'per 250 g',
];
const quickHourChoices = [1, 2, 3, 4];
const quickDayChoices = [1, 2, 3];

/// Where an item is in its life, as shown to its owner and the admin.
enum QuickPhase { pending, scheduled, live, expired, rejected, cancelled }

/// Reads a Firestore Timestamp, DateTime, ISO string or milliseconds.
DateTime? quickTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  try {
    return (value as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

DateTime? quickStartsAt(Entry item) => quickTime(item.data['startsAt']);
DateTime? quickExpiresAt(Entry item) => quickTime(item.data['expiresAt']);

/// pending / rejected / cancelled come straight from the status; an approved item is scheduled,
/// live or expired by the clock, so it disappears on time even before the server marks it.
QuickPhase quickPhase(Entry item, DateTime now) {
  switch (item.text('status')) {
    case 'approved':
      final start = quickStartsAt(item), end = quickExpiresAt(item);
      if (start == null || end == null) return QuickPhase.pending;
      if (!now.isBefore(end)) return QuickPhase.expired;
      return now.isBefore(start) ? QuickPhase.scheduled : QuickPhase.live;
    case 'rejected':
      return QuickPhase.rejected;
    case 'cancelled':
      return QuickPhase.cancelled;
    case 'expired':
      return QuickPhase.expired;
    default:
      return QuickPhase.pending;
  }
}

/// The three tabs of "My Items": Scheduled (waiting for approval or for the start time),
/// Live, and Expired (finished, rejected or cancelled).
enum QuickTab { scheduled, live, expired }

QuickTab quickTabOf(QuickPhase phase) => switch (phase) {
  QuickPhase.pending || QuickPhase.scheduled => QuickTab.scheduled,
  QuickPhase.live => QuickTab.live,
  _ => QuickTab.expired,
};

/// "2h 15m", "45m", "1d 3h": the time left, for "Available for 2h 15m".
String quickCountdown(Duration left) {
  if (left.isNegative || left.inMinutes < 1) return '<1m';
  final days = left.inDays, hours = left.inHours % 24, minutes = left.inMinutes % 60;
  if (days > 0) return hours > 0 ? '${days}d ${hours}h' : '${days}d';
  if (left.inHours > 0) return minutes > 0 ? '${left.inHours}h ${minutes}m' : '${left.inHours}h';
  return '${left.inMinutes}m';
}

/// The calendar day in India (IST) as YYYY-MM-DD: the day the daily limit counts in (same as the server's dayKey).
String quickDayKey(DateTime now) {
  final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${ist.year}-${two(ist.month)}-${two(ist.day)}';
}

/// Items per day for a role: the admin's setting (Business profile), else 15 staff / 6 vendors.
int quickDailyLimit(String role, Entry business) {
  final raw = business.number(role == 'staff' ? 'quickItemsPerDayStaff' : 'quickItemsPerDayVendor');
  return raw >= 1 && raw <= 1000 && raw == raw.roundToDouble() ? raw.round() : (role == 'staff' ? 15 : 6);
}

String quickDurationLabel(String unit, int value) =>
    unit == 'days' ? '$value ${value == 1 ? 'day' : 'days'}' : '$value ${value == 1 ? 'hour' : 'hours'}';

/// Whether an item is within [km] of the customer's point ([latitude], [longitude]), measured to the place the item was photographed
/// (its saved latitude / longitude): distance only, like everything customers see (lib/domain/reach.dart). An item without a saved
/// place, or a customer whose place is not known, never matches.
bool quickItemWithin(Entry item, {required double? latitude, required double? longitude, required double km}) {
  final lat = item.number('latitude'), lng = item.number('longitude');
  if (latitude == null || longitude == null || (lat == 0 && lng == 0)) return false;
  return distanceKm(latitude, longitude, lat, lng) <= km;
}

/// Live right now within [km] of the customer's point, optionally in one category: the customer's view.
List<Entry> liveQuickItems(
  Iterable<Entry> items,
  DateTime now, {
  required double? latitude,
  required double? longitude,
  required double km,
  String? categoryId,
}) {
  final live = items
      .where(
        (item) =>
            quickPhase(item, now) == QuickPhase.live &&
            quickItemWithin(item, latitude: latitude, longitude: longitude, km: km) &&
            (categoryId == null || item.text('categoryId') == categoryId),
      )
      .toList();
  // Ending soonest first, so the items about to go are seen first.
  live.sort((a, b) => quickExpiresAt(a)!.compareTo(quickExpiresAt(b)!));
  return live;
}
