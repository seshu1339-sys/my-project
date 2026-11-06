import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;

import '../domain/ist_time.dart';

/// The time the apps decide ad and offer start / end times by: the SERVER's clock, never the phone's.
///
/// Every app reads the `Date` header of a small request to its own website once at start (and every 30 minutes) and keeps the
/// difference to the phone's clock. [ServerClock.now] is then the phone's clock corrected by that difference, so a phone set to the
/// wrong day or hour still shows, hides and ends ads exactly when the server says. Until the first answer arrives (or with no
/// internet) the phone's own clock is used, and [synced] stays false.
///
/// Times the admin types are India time (IST, UTC+5:30): lib/domain/ist_time.dart.
class ServerClock {
  ServerClock._();

  static Duration _offset = Duration.zero;
  static bool _synced = false;
  static Timer? _timer;
  static DateTime Function() _device = DateTime.now;

  /// The server's time now (as a local DateTime of this device).
  static DateTime now() => _device().add(_offset);

  /// How far the phone's clock is from the server's (server minus phone).
  static Duration get offset => _offset;

  /// True once the server's time has been read at least once.
  static bool get synced => _synced;

  /// Where the time is read from: the website itself on the web, else SERVER_TIME_URL (default the live website).
  static Uri get _source {
    if (kIsWeb) return Uri.base.resolve('/favicon.png');
    const url = String.fromEnvironment('SERVER_TIME_URL', defaultValue: 'https://locamarket.in/favicon.png');
    return Uri.parse(url);
  }

  /// Reads the server's time now and every [every] after that. Never throws: without an answer the phone's clock stays in use.
  static Future<void> start({Duration every = const Duration(minutes: 30)}) async {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(sync()));
    await sync();
  }

  /// One reading. Returns true when the server answered with a usable Date header.
  static Future<bool> sync({http.Client? client, Uri? source}) async {
    final own = client == null;
    final c = client ?? http.Client();
    try {
      final base = source ?? _source;
      final sent = _device();
      final url = base.replace(queryParameters: {...base.queryParameters, 't': '${sent.millisecondsSinceEpoch}'});
      final response = await c.head(url).timeout(const Duration(seconds: 10));
      final received = _device();
      final server = parseHttpDate(response.headers['date'] ?? '');
      if (server == null) return false;
      // The header was made about half way through the round trip.
      final middle = sent.add(received.difference(sent) ~/ 2);
      _offset = server.difference(middle);
      _synced = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      if (own) c.close();
    }
  }

  @visibleForTesting
  static void debugSet({Duration offset = Duration.zero, bool synced = true, DateTime Function()? device}) {
    _offset = offset;
    _synced = synced;
    _device = device ?? DateTime.now;
  }

  @visibleForTesting
  static void debugReset() => debugSet(synced: false);
}
