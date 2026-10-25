import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'usage.dart';

/// Crashes and errors, and how fast the app starts, counted with the usage analytics (functions/usage.js: app_error, app_start) so
/// the admin's Setup check shows them for every app, the website included. The existing error handlers keep working as before.
/// Cost guard: at most [maxErrors] different errors are sent in one run, each once, so an error repeating every frame costs
/// nothing more. Emails, links and long numbers (phone numbers) are taken out of a message before it is sent.
class AppMonitoring {
  AppMonitoring._();

  static const maxErrors = 5;
  static String? _app;
  static final _sent = <String>{};
  static final _waiting = <(String, String, String)>[];

  /// The speed groups of the time from the app's code starting to its first screen.
  static const speedGroups = ['under 1 s', '1-2 s', '2-4 s', '4-8 s', 'over 8 s'];

  static String speedGroup(Duration d) {
    final ms = d.inMilliseconds;
    return ms < 1000
        ? speedGroups[0]
        : ms < 2000
        ? speedGroups[1]
        : ms < 4000
        ? speedGroups[2]
        : ms < 8000
        ? speedGroups[3]
        : speedGroups[4];
  }

  static String get _platform => kIsWeb ? 'web' : 'android';

  /// Call first thing in main(), after WidgetsFlutterBinding.ensureInitialized(). Never throws.
  static void start({required String app}) {
    if (_app != null) return;
    _app = app;
    final started = DateTime.now();
    try {
      final previousFlutter = FlutterError.onError;
      FlutterError.onError = (details) {
        report(details.exception);
        (previousFlutter ?? FlutterError.presentError)(details);
      };
      final previousPlatform = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        report(error, crash: true);
        return previousPlatform?.call(error, stack) ?? false;
      };
      WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
        final group = speedGroup(DateTime.now().difference(started));
        _send('app_start', '$app/$_platform/$group', group);
      });
    } catch (_) {
      /* monitoring must never stop the app */
    }
  }

  /// Counts one error (a crash when nothing caught it).
  static void report(Object error, {bool crash = false}) {
    final app = _app;
    if (app == null) return;
    try {
      final text = cleanMessage('${error.runtimeType}: $error');
      final key = '$app/$_platform/${crash ? 'crash' : 'error'}/${fingerprint(text)}';
      if (_sent.contains(key) || _sent.length >= maxErrors) return;
      _sent.add(key);
      _send('app_error', key, text);
    } catch (_) {
      /* never */
    }
  }

  /// The first line of [message] without emails, links or long numbers, cut to 100 characters.
  static String cleanMessage(String message) {
    final line = message.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
    final clean = line
        .replaceAll(RegExp(r'\S+@\S+'), '<email>')
        .replaceAll(RegExp(r'https?://\S+'), '<link>')
        .replaceAll(RegExp(r'\d{6,}'), '<number>')
        .replaceAll(RegExp(r'\s+'), ' ');
    return clean.length > 100 ? clean.substring(0, 100) : clean;
  }

  /// A short id for a message that stays the same on every device and run (FNV-1a).
  static String fingerprint(String text) {
    var h = 0x811c9dc5;
    for (final c in text.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  // Usage starts a little after the app (it waits for Firebase): what comes before waits, for up to a minute.
  static void _send(String event, String key, String label) {
    if (Usage.instance != null) return Usage.track(event, key: key, label: label);
    _waiting.add((event, key, label));
    if (_waiting.length > 1) return;
    var tries = 0;
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (Usage.instance == null && ++tries < 60) return;
      timer.cancel();
      final waiting = [..._waiting];
      _waiting.clear();
      for (final (e, k, l) in waiting) {
        Usage.track(e, key: k, label: l);
      }
    });
  }

  @visibleForTesting
  static void reset() {
    _app = null;
    _sent.clear();
    _waiting.clear();
  }
}
