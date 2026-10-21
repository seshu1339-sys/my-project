import 'package:flutter/material.dart';

import '../domain/catalog.dart';

/// The animations an admin can give a piece of banner text (the offer title,
/// e.g. "Big Savings Everyday", or the "Today's Offers" heading). Empty/'none'
/// leaves the text exactly as it was.
const textAnimationLabels = <String, String>{
  'fade': 'Fade in',
  'slideUp': 'Slide up',
  'slideLeft': 'Slide in from the right',
  'slideRight': 'Slide in from the left',
  'zoom': 'Zoom in',
  'bounce': 'Bounce in',
  'pulse': 'Pulse (keeps beating)',
};

/// Wraps [child] in the animation named by [entry]'s [key] field. Entrance
/// animations play once when the text appears; 'pulse' repeats. With the OS
/// "reduce motion" setting on, nothing moves.
Widget animatedText(Entry entry, String key, Widget child) {
  final type = entry.text(key);
  if (!textAnimationLabels.containsKey(type)) return child;
  return TextEffect(type: type, child: child);
}

class TextEffect extends StatefulWidget {
  const TextEffect({super.key, required this.type, required this.child});
  final String type;
  final Widget child;
  @override
  State<TextEffect> createState() => _TextEffectState();
}

class _TextEffectState extends State<TextEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.type == 'pulse' ? 900 : 700),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else if (widget.type == 'pulse') {
      _controller.repeat(reverse: true);
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final t = _controller.value;
      switch (widget.type) {
        case 'fade':
          return Opacity(opacity: t, child: child);
        case 'slideUp':
          return Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
          );
        case 'slideLeft':
          return Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(40 * (1 - t), 0), child: child),
          );
        case 'slideRight':
          return Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(-40 * (1 - t), 0), child: child),
          );
        case 'zoom':
          return Opacity(
            opacity: t,
            child: Transform.scale(scale: .6 + .4 * t, alignment: Alignment.centerLeft, child: child),
          );
        case 'bounce':
          return Opacity(
            opacity: t.clamp(0, 1),
            child: Transform.translate(
              offset: Offset(0, -28 * (1 - Curves.bounceOut.transform(t))),
              child: child,
            ),
          );
        case 'pulse':
          return Transform.scale(scale: 1 + .06 * t, alignment: Alignment.centerLeft, child: child);
      }
      return child!;
    },
  );
}
