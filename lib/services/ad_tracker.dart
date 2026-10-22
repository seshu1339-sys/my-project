import 'dart:async';

/// Reports what happens to each ad to the server in small batches (the callable `trackAdEvents`, functions/ad-tracking.js). The server
/// decides what counts; this class only avoids sending what can never count (a second view of the same ad within 30 minutes) and keeps
/// the number of calls small.
///
/// Events: `view` (on screen for a second), `time` (more seconds on screen), `miss` (scheduled but never visible), `tap`.
class AdsTracker {
  AdsTracker({
    required this.visitorId,
    required this.platform,
    required this.transport,
    this.flushEvery = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String visitorId, platform;
  final Future<void> Function(Map<String, Object?> batch) transport;
  final Duration flushEvery;
  final DateTime Function() _now;

  /// The tracker the customer app uses, set once Firebase is connected (null in demo mode and in the admin / vendor apps).
  static AdsTracker? instance;

  static const viewGap = Duration(minutes: 30);
  final _queue = <Map<String, Object?>>[];
  final _viewed = <String, DateTime>{};
  Timer? _timer;

  int get pending => _queue.length;

  void _add(String type, String adId, String town, [int seconds = 0]) {
    _queue.add({'type': type, 'adId': adId, 'seconds': seconds, '_town': town});
    _timer ??= Timer(flushEvery, flush);
  }

  /// The ad has now been on screen for a second. A repeat within 30 minutes is not sent at all.
  void view(String adId, {String town = ''}) {
    final last = _viewed[adId];
    if (last != null && _now().difference(last) < viewGap) return;
    _viewed[adId] = _now();
    _add('view', adId, town, 1);
  }

  /// More seconds on screen after the first one; only for an ad whose view was sent.
  void time(String adId, int seconds, {String town = ''}) {
    if (seconds <= 0 || !_viewed.containsKey(adId)) return;
    _add('time', adId, town, seconds);
  }

  /// The ad was due on screen but was not visible for a second.
  void miss(String adId, {String town = ''}) => _add('miss', adId, town);

  void tap(String adId, {String town = ''}) => _add('tap', adId, town);

  /// Sends everything waiting, one batch per town (at most 50 events each). A failed send is dropped: counting must never get in the way.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_queue.isEmpty) return;
    final events = [..._queue];
    _queue.clear();
    final byTown = <String, List<Map<String, Object?>>>{};
    for (final e in events) {
      byTown.putIfAbsent('${e['_town']}', () => []).add({'type': e['type'], 'adId': e['adId'], 'seconds': e['seconds']});
    }
    for (final entry in byTown.entries) {
      for (var i = 0; i < entry.value.length; i += 50) {
        try {
          await transport({
            'visitorId': visitorId,
            'platform': platform,
            'town': entry.key,
            'events': entry.value.sublist(i, i + 50 > entry.value.length ? entry.value.length : i + 50),
          });
        } catch (_) {
          /* best effort */
        }
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
