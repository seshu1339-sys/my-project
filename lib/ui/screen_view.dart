import 'package:flutter/widgets.dart';

import '../services/usage.dart';

/// Counts one view of the screen [name] each time it opens (Usage.screen; the names are in lib/services/usage_buttons.dart).
/// Shows [child] unchanged.
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
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
