import 'package:flutter/widgets.dart';

import '../services/app_monitoring.dart';
import '../services/usage.dart';

/// Counts one view of the screen [name] each time it opens (Usage.screen; the names are in lib/services/usage_buttons.dart), names it
/// as the open screen for the problems the app reports, and reports it as slow when its first frame takes over
/// [AppMonitoring.slowScreen] (owner spec G). Shows [child] unchanged.
class ScreenView extends StatefulWidget {
  const ScreenView(this.name, {super.key, required this.child});
  final String name;
  final Widget child;
  @override
  State<ScreenView> createState() => _ScreenViewState();
}

class _ScreenViewState extends State<ScreenView> {
  @override
  void initState() {
    super.initState();
    Usage.screen(widget.name);
    AppMonitoring.screen = widget.name;
    final opened = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final took = DateTime.now().difference(opened);
      if (took > AppMonitoring.slowScreen) AppMonitoring.fail('slow', 'Slow screen ${widget.name}', ms: took.inMilliseconds);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
