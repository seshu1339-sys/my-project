import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/support_case.dart';
import '../domain/support_limits.dart';
import '../services/app_monitoring.dart';
import '../services/difficulty_watch.dart';
import '../services/screen_capture.dart';
import '../domain/support_texts.dart';
import 'my_support_page.dart';

/// Wraps every app (the website, the admin panel and the Vendor, Staff and User Android apps; each MaterialApp's builder) for the AI
/// Agent + Health System (17 Nov 2026):
///   * the screen area the automatic screenshot is taken from (lib/services/screen_capture.dart);
///   * the taps, hangs and stuck loading watched on every screen (lib/services/difficulty_watch.dart);
///   * the admin's limits (settings/health) kept up to date;
///   * when a case the person met happens: the option is highlighted and the AI Support box opens (lib/ui/ai_support_box.dart, part 3).
Widget withSupportShell(BuildContext context, Widget? child, Store store) => SupportShell(store: store, child: child ?? const SizedBox.shrink());

class SupportShell extends StatefulWidget {
  const SupportShell({super.key, required this.store, required this.child});
  final Store store;
  final Widget child;

  /// The box shown for a case (set by part 3); null shows only the highlight.
  static Widget Function(BuildContext context, Store store, SupportCase c, VoidCallback close)? boxBuilder;

  @override
  State<SupportShell> createState() => SupportShellState();
}

class SupportShellState extends State<SupportShell> with WidgetsBindingObserver {
  SupportCase? current;
  Rect? highlight;
  Timer? _highlightOff, _replyCheck;

  /// The LocaMarket team replied to one of the person's reports since they last looked.
  bool replied = false;

  /// The problems the box was shown for in this session (the same problem never opens it twice).
  static final shown = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppMonitoring.onSupportCase = _onCase;
    DifficultyWatch.start();
    widget.store.addListener(_limits);
    _limits();
    // A few seconds after the app opens: did the team reply? (only for people who sent a report; see MySupportPage.hasNewReply)
    _replyCheck = Timer(const Duration(seconds: 8), () async {
      if (!widget.store.live) return;
      final yes = await MySupportPage.hasNewReply(widget.store);
      if (yes && mounted) setState(() => replied = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_limits);
    if (AppMonitoring.onSupportCase == _onCase) AppMonitoring.onSupportCase = null;
    DifficultyWatch.stop();
    _highlightOff?.cancel();
    _replyCheck?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) DifficultyWatch.resumed();
  }

  void _limits() {
    final s = widget.store.entries('settings');
    Duration secs(String id) => Duration(milliseconds: (limitValue(s, id) * 1000).round());
    AppMonitoring.slowScreen = secs('slowScreenSeconds');
    AppMonitoring.slowSave = secs('slowSaveSeconds');
    DifficultyWatch.loadingAfter = secs('loadingSeconds');
    DifficultyWatch.freezeAfter = secs('freezeSeconds');
  }

  void _onCase(SupportCase c) {
    if (!mounted) return;
    // Called from inside a build or a gesture: show on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (c.rect != null) {
        setState(() => highlight = c.rect);
        _highlightOff?.cancel();
        _highlightOff = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => highlight = null);
        });
      }
      if (current != null || !shown.add(c.fingerprint)) return;
      if (SupportShell.boxBuilder != null) setState(() => current = c);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void close() => setState(() => current = null);

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: DifficultyWatch.pointerDown,
    onPointerUp: DifficultyWatch.pointerUp,
    child: Stack(children: [
      Positioned.fill(child: RepaintBoundary(key: ScreenCapture.boundaryKey, child: widget.child)),
      if (highlight != null)
        Positioned.fromRect(
          rect: highlight!.inflate(4),
          child: IgnorePointer(
            child: Container(
              key: const ValueKey('support-highlight'),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFFB300), width: 3), borderRadius: BorderRadius.circular(8), color: const Color(0x22FFB300)),
            ),
          ),
        ),
      if (current != null && SupportShell.boxBuilder != null) SupportShell.boxBuilder!(context, widget.store, current!, close),
      if (replied && current == null) Positioned(left: 12, right: 12, bottom: 24, child: _ReplyNotice(store: widget.store, close: () => setState(() => replied = false))),
    ]),
  );
}

/// "LocaMarket team replied to your problem" with Open (My problem reports) and Close.
class _ReplyNotice extends StatelessWidget {
  const _ReplyNotice({required this.store, required this.close});
  final Store store;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final lang = supportLang(store.language);
    return Material(
      key: const ValueKey('support-reply-notice'),
      elevation: 8,
      color: const Color(0xFF2E7D32),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(children: [
          const Icon(Icons.mark_chat_read_outlined, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(supportWord('newReply', lang), style: const TextStyle(color: Colors.white))),
          TextButton(
            onPressed: () {
              close();
              SupportNavigatorObserver.last?.navigator?.push(MaterialPageRoute<void>(builder: (_) => MySupportPage(store: store)));
            },
            child: Text(supportWord('open', lang), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          IconButton(onPressed: close, icon: const Icon(Icons.close, color: Colors.white70)),
        ]),
      ),
    );
  }
}
