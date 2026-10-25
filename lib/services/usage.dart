import 'dart:async';

import '../domain/catalog.dart';

/// Usage analytics: what people do in the apps (the admin's Analytics reports, and each vendor's, provider's and staff member's own
/// numbers). Events go to the server in small batches (the callable `trackUsage`, functions/usage.js), which decides what counts
/// and keeps only counts. Every call is best-effort: counting must never slow down or break the app.
///
/// The events (functions/usage.js CLIENT_EVENTS): shop_call, shop_whatsapp, shop_directions, worker_call, worker_whatsapp, map_view,
/// price_list_view, service_open, search, search_no_result, location_change, offer_click, transport_click, screen_view, button,
/// notification_open. [key] says what it was about (a shop id, an item, a town...), [label] the name people read.
class Usage {
  Usage({
    required this.app,
    required this.deviceId,
    required this.platform,
    required this.transport,
    this.flushEvery = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String app, deviceId, platform;
  final Future<void> Function(Map<String, Object?> batch) transport;
  final Duration flushEvery;
  final DateTime Function() _now;

  /// The tracker of this app, set once Firebase is connected (null in the demo and in tests: then nothing is counted).
  static Usage? instance;

  /// Also given every event (Firebase Analytics, lib/services/app_monitoring.dart).
  static final sinks = <void Function(String event, Map<String, String> params)>[];

  /// Counts [event] in this app (nothing when the app has no tracker).
  static void track(String event, {String key = '', String label = '', String town = ''}) {
    instance?.add(event, key: key, label: label, town: town);
    final params = {if (key.isNotEmpty) 'key': key, if (label.isNotEmpty) 'label': label, if (town.isNotEmpty) 'town': town};
    for (final sink in sinks) {
      try {
        sink(event, params);
      } catch (_) {
        /* a sink must never break the app */
      }
    }
  }

  /// A screen was opened.
  static void screen(String name) => track('screen_view', key: name, label: name);

  /// A button or option was used (see lib/services/usage_buttons.dart for the list the admin sees).
  static void button(String id, {String label = ''}) => track('button', key: id, label: label.isEmpty ? id : label);

  /// When the account's activity was last reported (at most every [touchEvery]).
  static const touchEvery = Duration(hours: 6);
  final _queue = <Map<String, Object?>>[];
  Timer? _timer;
  DateTime? _touchedAt;

  int get pending => _queue.length;

  void add(String event, {String key = '', String label = '', String town = ''}) {
    _queue.add({'event': event, 'key': key, 'label': label, 'town': town});
    _timer ??= Timer(flushEvery, flush);
  }

  /// Says the account is using the app (the admin's inactive-accounts list), without waiting for an event.
  void touch() {
    _touchedAt = null;
    _timer ??= Timer(Duration.zero, flush);
  }

  /// Sends everything waiting, at most 50 events a batch. A failed send is dropped.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final touch = _touchedAt == null || _now().difference(_touchedAt!) >= touchEvery;
    if (_queue.isEmpty && !touch) return;
    if (touch) _touchedAt = _now();
    final events = [..._queue];
    _queue.clear();
    var first = true;
    for (var i = 0; i < events.length || first; i += 50) {
      try {
        await transport({
          'deviceId': deviceId,
          'app': app,
          'platform': platform,
          'touch': touch && first,
          'events': events.sublist(i.clamp(0, events.length), (i + 50).clamp(0, events.length)),
        });
      } catch (_) {
        /* best effort */
      }
      first = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// A customer contacted a shop by calling or on WhatsApp (shop_call, shop_whatsapp); other ways are not counted.
void trackShopContact(String way, Entry shop) {
  if (way != 'call' && way != 'whatsapp') return;
  Usage.track(way == 'call' ? 'shop_call' : 'shop_whatsapp', key: shop.id, label: shop.text('name'), town: shop.text('town'));
}
