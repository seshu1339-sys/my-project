import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../domain/problem_cause.dart';
import 'app_monitoring.dart';

/// Difficulty without an error (AI Agent + Health System part 2, 17 Nov 2026), on every screen of every app:
///   * the same option tapped 3 times within 5 seconds with nothing happening (no new screen, no dialog): "no answer";
///   * the app not answering for [freezeAfter] (a hang; Android's own "app not responding" also goes to Crashlytics);
///   * a screen still showing a loading circle after [loadingAfter] ("stuck loading").
/// Each is one case through [AppMonitoring.fail] (recorded with its screenshot; the AI Support box opens). The option tapped last is
/// kept in [AppMonitoring.lastTap] so a failure right after a tap names and highlights that option.
class DifficultyWatch {
  DifficultyWatch._();

  static Duration freezeAfter = const Duration(seconds: 3);
  static Duration loadingAfter = const Duration(seconds: 20);
  static const tapsForNoAnswer = 3;
  static const tapWindow = Duration(seconds: 5);

  /// Goes up each time a screen or dialog opens or closes ([SupportNavigatorObserver]); taps across a change are not "no answer".
  static int routeToken = 0;

  static Timer? _beat, _scan;
  static DateTime _lastBeat = DateTime.now();
  static Offset? _downAt;
  static DateTime? _downTime;
  static final _taps = <({String label, Offset at, DateTime time, int token})>[];
  static DateTime? _loadingSince;
  static String _loadingKey = '';
  static final _stuckReported = <String>{};

  static bool get _resumed {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  /// Starts the hang watch and the loading scan (once). Never throws.
  static void start() {
    if (_beat != null) return;
    _lastBeat = DateTime.now();
    _beat = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick(DateTime.now()));
    _scan = Timer.periodic(const Duration(seconds: 4), (_) => _scanLoading(DateTime.now()));
  }

  static void stop() {
    _beat?.cancel();
    _scan?.cancel();
    _beat = null;
    _scan = null;
  }

  /// A heartbeat on the app's main thread: a long gap between beats while the app is in front is a hang.
  static void _tick(DateTime now) {
    final gap = now.difference(_lastBeat);
    _lastBeat = now;
    if (!_resumed) return;
    if (gap > freezeAfter && gap < const Duration(minutes: 5)) {
      AppMonitoring.fail('freeze', 'App did not answer for ${(gap.inMilliseconds / 1000).toStringAsFixed(1)} s on ${AppMonitoring.screen.isEmpty ? 'a screen' : AppMonitoring.screen}', ms: gap.inMilliseconds);
    }
  }

  /// The app came back to the front: the time it was away is not a hang.
  static void resumed() => _lastBeat = DateTime.now();

  // ---- taps ----

  static void pointerDown(PointerDownEvent e) {
    _downAt = e.position;
    _downTime = DateTime.now();
  }

  static void pointerUp(PointerUpEvent e) {
    final at = _downAt, t = _downTime;
    _downAt = null;
    if (at == null || t == null) return;
    if ((e.position - at).distance > 18 || DateTime.now().difference(t) > const Duration(milliseconds: 700)) return; // a drag or a long press
    try {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, e.position, e.viewId);
      final target = describeTap(hit, e.position);
      if (target == null) return;
      AppMonitoring.lastTap = (label: target.label, rect: target.rect, at: DateTime.now());
      tapped(target.label, e.position, rect: target.rect);
    } catch (_) {/* never */}
  }

  /// One tap on [label] at [at]. The third tap on the same option within [tapWindow] with no screen change is "no answer".
  static void tapped(String label, Offset at, {Rect? rect, DateTime? now}) {
    final time = now ?? DateTime.now();
    if (isRepeatTapOption(label)) return;
    _taps.removeWhere((x) => time.difference(x.time) > tapWindow || x.token != routeToken || x.label != label || (x.at - at).distance > 40);
    _taps.add((label: label, at: at, time: time, token: routeToken));
    if (_taps.length >= tapsForNoAnswer) {
      _taps.clear();
      final name = label.isEmpty ? 'an option' : '"$label"';
      AppMonitoring.fail('tap', 'No answer to $name after $tapsForNoAnswer taps', option: label, rect: rect);
    }
  }

  /// The option under a tap: its words (or "icon") and its box on the screen. Null for a text field or the keyboard area.
  static ({String label, Rect? rect})? describeTap(HitTestResult hit, Offset position) {
    String label = '';
    Rect? rect;
    for (final entry in hit.path) {
      final o = entry.target;
      if (o is RenderEditable) return null;
      if (label.isEmpty && o is RenderParagraph) {
        final text = o.text.toPlainText().trim();
        if (RegExp(r'[A-Za-zऀ-෿]').hasMatch(text)) label = text.length > 60 ? text.substring(0, 60) : text;
      }
      if (rect == null && o is RenderBox && o.hasSize && o.size.width >= 32 && o.size.height >= 24 && o.size.width < 700 && o.size.height < 200) {
        try {
          rect = MatrixUtils.transformRect(o.getTransformTo(null), Offset.zero & o.size);
        } catch (_) {}
      }
    }
    return (label: label.isEmpty ? 'icon' : label, rect: rect);
  }

  // ---- loading ----

  static void _scanLoading(DateTime now) {
    if (!_resumed) {
      _loadingSince = null;
      return;
    }
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    final loading = hasVisibleLoading(root);
    final key = '${AppMonitoring.screen}#$routeToken';
    if (!loading || key != _loadingKey) {
      _loadingKey = key;
      _loadingSince = loading ? now : null;
      return;
    }
    final since = _loadingSince ??= now;
    if (now.difference(since) > loadingAfter && _stuckReported.add(key)) {
      AppMonitoring.fail('stuck', 'Still loading after ${now.difference(since).inSeconds} s on ${AppMonitoring.screen.isEmpty ? 'a screen' : AppMonitoring.screen}', ms: now.difference(since).inMilliseconds);
    }
  }

  /// True when a loading circle / bar without an end (value null) shows on the screen in front. Pull-to-refresh and the screens
  /// behind the front one (their tickers are off) do not count.
  static bool hasVisibleLoading(Element root) {
    var found = false;
    var visited = 0;
    void visit(Element e) {
      if (found || ++visited > 40000) return;
      final w = e.widget;
      if ((w is CircularProgressIndicator && w.value == null && w is! RefreshProgressIndicator) || (w is LinearProgressIndicator && w.value == null)) {
        final ticker = e.findAncestorWidgetOfExactType<TickerMode>();
        if (ticker == null || ticker.enabled) {
          found = true;
          return;
        }
      }
      e.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    return found;
  }

  @visibleForTesting
  static void reset() {
    stop();
    _taps.clear();
    _stuckReported.clear();
    _loadingSince = null;
    _loadingKey = '';
    routeToken = 0;
  }
}

/// Counts screen and dialog changes (for the "no answer" rule) and names the screen from the route when it has a name. Added to every
/// app's MaterialApp (navigatorObservers).
class SupportNavigatorObserver extends NavigatorObserver {
  SupportNavigatorObserver._();

  /// The one observer of the app's navigator (each app has one MaterialApp, rebuilt often: the same observer every time).
  static final shared = SupportNavigatorObserver._();

  /// The observer of the app's own navigator (the AI Support box sits above it and opens pages through it).
  static SupportNavigatorObserver? get last => shared;

  void _changed(Route<dynamic>? route) {
    DifficultyWatch.routeToken++;
    final name = route?.settings.name;
    if (name != null && name.isNotEmpty && name != '/') AppMonitoring.screen = name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _changed(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _changed(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _changed(newRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _changed(previousRoute);
}
