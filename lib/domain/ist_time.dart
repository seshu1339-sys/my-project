// India time (IST, UTC+5:30) for ad and offer start / end times. Pure functions, no clock of their own: the time "now" comes from
// lib/services/server_clock.dart (the server's clock, never the phone's).

const _ist = Duration(hours: 5, minutes: 30);

/// An ad / offer time as saved: an ISO date-time. One with its own zone (Z or +05:30) is that moment; one without a zone is India time
/// (IST), whatever the phone's own time zone is. Null when blank or not a date.
DateTime? parseIstTime(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(v);
  if (hasZone) return DateTime.tryParse(v);
  final local = DateTime.tryParse(v);
  if (local == null) return null;
  // Read the digits as India time.
  return DateTime.utc(local.year, local.month, local.day, local.hour, local.minute, local.second, local.millisecond).subtract(_ist);
}

/// The India wall-clock time of [moment] (a UTC DateTime whose fields read as IST).
DateTime istWallClock(DateTime moment) => moment.toUtc().add(_ist);

/// "2026-11-06T10:15:00+05:30": the India date and time of [moment], saved with its zone so every phone reads the same moment.
String istIso(DateTime moment) {
  final w = istWallClock(moment);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${w.year.toString().padLeft(4, '0')}-${two(w.month)}-${two(w.day)}T${two(w.hour)}:${two(w.minute)}:${two(w.second)}+05:30';
}

/// The India moment for a date and time picked in the admin panel (the digits are India time).
DateTime istMoment(int year, int month, int day, [int hour = 0, int minute = 0]) => DateTime.utc(year, month, day, hour, minute).subtract(_ist);

/// "6 Nov 2026, 10:15 am" in India time, or '' for null.
String istLabel(DateTime? moment) {
  if (moment == null) return '';
  const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final w = istWallClock(moment);
  final hour = w.hour % 12 == 0 ? 12 : w.hour % 12;
  return '${w.day} ${names[w.month - 1]} ${w.year}, $hour:${w.minute.toString().padLeft(2, '0')} ${w.hour < 12 ? 'am' : 'pm'}';
}

const _months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

/// "Thu, 06 Nov 2026 10:15:30 GMT" (the HTTP Date header) -> that moment, or null.
DateTime? parseHttpDate(String value) {
  final m = RegExp(r'(\d{1,2})[ -]([A-Za-z]{3})[ -](\d{2,4}) (\d{2}):(\d{2}):(\d{2})').firstMatch(value);
  if (m == null) return null;
  final month = _months[m[2]!.toLowerCase()];
  if (month == null) return null;
  var year = int.parse(m[3]!);
  if (year < 100) year += 2000;
  return DateTime.utc(year, month, int.parse(m[1]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
}
