import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/analytics.dart';

/// Counts an impression once this ad is actually on screen: at least half of it
/// inside the visible window while the app is in the foreground. The page builds
/// everything up front, so merely being built must not count as being seen.
/// Purely observational: it draws exactly its child.
class ImpressionOnce extends StatefulWidget {
  const ImpressionOnce({super.key, required this.entry, required this.child});
  final Entry entry;
  final Widget child;
  @override
  State<ImpressionOnce> createState() => _ImpressionOnceState();
}

class _ImpressionOnceState extends State<ImpressionOnce> {
  Timer? _timer;
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_counted || !mounted) return;
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return;
    }
    final window = Offset.zero & MediaQuery.sizeOf(context);
    final shown = (box.localToGlobal(Offset.zero) & box.size).intersect(window);
    if (shown.isEmpty) return;
    if (shown.width * shown.height >= box.size.width * box.size.height * 0.5) {
      _counted = true;
      _timer?.cancel();
      Analytics.impression(widget.entry);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
