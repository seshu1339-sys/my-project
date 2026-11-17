import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'usage.dart';

/// Crashes, errors, key failures and how fast the app starts, from every app (the website, the admin panel, and the Vendor, Staff and
/// User Android apps) for the admin's Health and App Health pages (owner spec F + G, 17 Nov 2026):
///   * counted with the usage analytics as before (functions/usage.js: app_error, app_start), for the Setup check;
///   * sent with the app name, version, device and screen to functions/modules/app-problems reportAppProblems (the signed-in Vendor /
///     Staff ID is added by the server), for the App Health dashboard;
///   * on Android, also to Firebase Crashlytics (free) with the full stack, once Firebase is up ([firebaseReady]).
/// Key failures ([fail]): login, OTP, email verification, location permission, photo upload, server (API) errors, slow screens.
/// Cost guard: at most [maxErrors] different problems are sent in one run, each once, so a problem repeating every frame costs nothing
/// more (and the server keeps a daily cap per device). Emails, links and long numbers are taken out of a message before it is sent.
class AppMonitoring {
  AppMonitoring._();

  static const maxErrors = 8;

  /// A screen slower than this to show its first frame is reported as slow.
  static const slowScreen = Duration(milliseconds: 2500);
  static const kinds = ['crash', 'error', 'login', 'otp', 'email', 'location', 'upload', 'api', 'slow'];
  static String? _app;
  static final _sent = <String>{};
  static final _waiting = <(String, String, String)>[];
  static final _problems = <Map<String, Object?>>[];
  static Timer? _flush;
  static bool _firebase = false, _crashlytics = false;
  static String _version = '', _device = '', _deviceId = '';

  /// The screen open now (ScreenView sets it), sent with each problem.
  static String screen = '';

  /// Test seam: where problems go instead of the server.
  @visibleForTesting
  static List<Map<String, Object?>>? testSink;

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
        report(details.exception, stack: details.stack);
        if (_crashlytics) FirebaseCrashlytics.instance.recordFlutterError(details);
        (previousFlutter ?? FlutterError.presentError)(details);
      };
      final previousPlatform = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        report(error, crash: true, stack: stack);
        if (_crashlytics) FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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

  /// Call once Firebase is connected: turns on Crashlytics (Android only) and starts sending the problems kept so far. Never throws.
  static Future<void> firebaseReady() async {
    if (_firebase) return;
    _firebase = true;
    try {
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final web = await plugin.webBrowserInfo;
        _device = '${web.browserName.name} ${web.platform ?? ''}'.trim();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await plugin.androidInfo;
        _device = '${a.manufacturer} ${a.model} (Android ${a.version.release})';
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('problemDeviceId') ?? '';
      if (_deviceId.isEmpty) {
        final r = Random.secure();
        _deviceId = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
        await prefs.setString('problemDeviceId', _deviceId);
      }
    } catch (_) {}
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
        await FirebaseCrashlytics.instance.setCustomKey('app', _app ?? '');
        _crashlytics = true;
      } catch (_) {}
    }
    _scheduleFlush();
  }

  /// The signed-in person's Vendor / Staff ID for Crashlytics (the server adds it to the problems it keeps). '' when signed out.
  static void setUser(String role, String code) {
    if (!_crashlytics) return;
    try {
      FirebaseCrashlytics.instance.setUserIdentifier(code);
      FirebaseCrashlytics.instance.setCustomKey('role', role);
    } catch (_) {}
  }

  /// Counts one error (a crash when nothing caught it).
  static void report(Object error, {bool crash = false, StackTrace? stack}) {
    _problem(crash ? 'crash' : 'error', '${error.runtimeType}: $error', counted: true);
  }

  /// One key failure: [kind] is one of [kinds] (login, otp, email, location, upload, api, slow).
  static void fail(String kind, String message, {int? ms}) {
    _problem(kinds.contains(kind) ? kind : 'error', message, ms: ms);
    if (_crashlytics) {
      try {
        FirebaseCrashlytics.instance.log('$kind: ${cleanMessage(message)}');
      } catch (_) {}
    }
  }

  /// A server call failed: login / OTP / email calls always count; other calls only when the server itself broke (not a "please fill
  /// in" answer).
  static void callFailed(String name, String code, String? message) {
    final lower = name.toLowerCase();
    final kind = lower.contains('otp') || lower.contains('logincode')
        ? 'otp'
        : lower.contains('role') || lower.contains('login') || lower.contains('signin')
        ? 'login'
        : lower.contains('email')
        ? 'email'
        : 'api';
    if (kind == 'api' && !const {'internal', 'unavailable', 'deadline-exceeded', 'unknown', 'not-found', 'data-loss'}.contains(code)) return;
    fail(kind, '$name: $code ${message ?? ''}'.trim());
  }

  static void _problem(String kind, String message, {bool counted = false, int? ms}) {
    final app = _app;
    if (app == null) return;
    try {
      final text = cleanMessage(message);
      final id = '$kind/${fingerprint(text)}';
      if (_sent.contains(id) || _sent.length >= maxErrors) return;
      _sent.add(id);
      if (counted) _send('app_error', '$app/$_platform/$kind/${fingerprint(text)}', text);
      _problems.add({'kind': kind, 'message': text, 'screen': screen, 'ms': ?ms});
      _scheduleFlush();
    } catch (_) {
      /* never */
    }
  }

  static void _scheduleFlush() {
    if (_problems.isEmpty || (!_firebase && testSink == null)) return;
    _flush?.cancel();
    _flush = Timer(const Duration(seconds: 3), _sendProblems);
  }

  static Future<void> _sendProblems() async {
    final batch = [..._problems];
    _problems.clear();
    if (batch.isEmpty) return;
    final data = {'app': _app, 'platform': _platform, 'version': _version, 'device': _device, 'deviceId': _deviceId, 'problems': batch};
    if (testSink != null) {
      testSink!.add(data);
      return;
    }
    try {
      await FirebaseFunctions.instance.httpsCallable('reportAppProblems').call(data);
    } catch (_) {
      /* a problem that cannot be sent is dropped; the app goes on */
    }
  }

  /// What the "Report a problem" form sends with the person's words.
  static Map<String, Object?> reportHeader() => {'app': _app ?? 'customer', 'platform': _platform, 'version': _version, 'device': _device, 'deviceId': _deviceId, 'screen': screen};

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

  /// Sends what is waiting now (tests).
  @visibleForTesting
  static Future<void> flushNow() async {
    _flush?.cancel();
    await _sendProblems();
  }

  @visibleForTesting
  static void reset() {
    _app = null;
    _sent.clear();
    _waiting.clear();
    _problems.clear();
    _flush?.cancel();
    _firebase = false;
    _crashlytics = false;
    screen = '';
  }
}
