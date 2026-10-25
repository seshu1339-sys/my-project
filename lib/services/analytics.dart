import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/catalog.dart';
import 'ad_tracker.dart';
import 'usage.dart';

/// Anonymous, aggregate-only site and ad analytics for the customer app.
///
/// A random id generated on the device tells visitors apart; nothing personal
/// is sent. Every call is fire-and-forget: analytics must never slow down or
/// break browsing, so failures are swallowed. Only the customer app starts it
/// (see main.dart), so the admin and vendor apps never produce events.
class Analytics {
  Analytics._();
  static bool _enabled = false;
  static String _visitorId = '';
  static final Map<String, DateTime> _lastImpression = {};
  // An ad on screen for a long time is one impression per this many minutes.
  static const _impressionGap = Duration(minutes: 30);

  static bool get enabled => _enabled;

  /// The random device id (empty until [start] has run), also used to count ad views.
  static String get visitorId => _visitorId;

  /// Starts counting genuine ad views (see AdsTracker): called once Firebase is connected.
  static void startAdTracker() {
    if (!_enabled || AdsTracker.instance != null) return;
    AdsTracker.instance = AdsTracker(
      visitorId: _visitorId,
      platform: kIsWeb ? 'web' : 'android',
      transport: (batch) => FirebaseFunctions.instance.httpsCallable('trackAdEvents').call(batch),
    );
  }

  /// Call once per app or site open, after Firebase is connected.
  static Future<void> start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('visitorId') ?? '';
      if (!RegExp(r'^[a-zA-Z0-9-]{16,64}$').hasMatch(id)) {
        final random = Random.secure();
        id = List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
        await prefs.setString('visitorId', id);
      }
      _visitorId = id;
      _enabled = true;
      // A visit that arrived through an ad link (?ad=<promotion id>) is credited to that ad.
      final source = kIsWeb ? Uri.base.queryParameters['ad'] : null;
      _send('visit', {if (source != null && source.isNotEmpty) 'sourceAd': source});
    } catch (_) {
      /* Analytics must never prevent the app from starting. */
    }
  }

  /// An ad was shown. Counted at most once per ad per 30 minutes per session.
  static void impression(Entry ad) {
    if (!_enabled || ad.id.isEmpty) return;
    final now = DateTime.now();
    final last = _lastImpression[ad.id];
    if (last != null && now.difference(last) < _impressionGap) return;
    _lastImpression[ad.id] = now;
    _send('adImpression', {'adId': ad.id, 'placement': ad.text('placement')});
  }

  /// An ad was tapped. Every tap counts.
  static void click(Entry ad) {
    // Usage analytics: which offer box was tapped (counted even before the visit counter has started).
    if (ad.id.isNotEmpty) Usage.track('offer_click', key: ad.id, label: ad.text('name', ad.text('title', ad.id)), town: ad.text('town'));
    if (!_enabled || ad.id.isEmpty) return;
    _send('adClick', {'adId': ad.id, 'placement': ad.text('placement')});
  }

  static void _send(String type, Map<String, Object?> extra) {
    unawaited(() async {
      try {
        await FirebaseFunctions.instance.httpsCallable('trackEvent').call({
          'visitorId': _visitorId,
          'type': type,
          'platform': kIsWeb ? 'web' : 'android',
          ...extra,
        });
      } catch (_) {
        /* Analytics is best-effort. */
      }
    }());
  }
}
