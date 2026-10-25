import 'package:flutter/widgets.dart';

/// Whether the widget at [context] is really in front of the customer: the app or tab active, its page on top, and at least half of
/// it on the screen. Ad views are counted only then (lib/services/ad_tracker.dart).
bool adMostlyOnScreen(BuildContext context) {
  final state = WidgetsBinding.instance.lifecycleState;
  if (state != null && state != AppLifecycleState.resumed) return false;
  if (ModalRoute.of(context)?.isCurrent == false) return false;
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) return false;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final seen = rect.intersect(Offset.zero & MediaQuery.sizeOf(context));
  return !seen.isEmpty && seen.width * seen.height >= .5 * rect.width * rect.height;
}
