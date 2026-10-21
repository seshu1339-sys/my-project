import 'dart:math' as math;

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
  'flip3d': '3D Flip (flips in on the horizontal axis)',
  'rotate3d': '3D Rotate (turns in on the vertical axis)',
  'spin': 'Spin in (360 degrees while appearing)',
  'flipLeft': 'Flip from left',
  'flipRight': 'Flip from right',
  'cube': 'Cube rotate (turns like a cube face)',
};

// Perspective so the 3D turns look deep rather than flat.
Matrix4 _perspective() => Matrix4.identity()..setEntry(3, 2, 0.001);

/// Wraps [child] in the animation named by [entry]'s [key] field. Entrance
/// animations play once when the text appears; 'pulse' repeats. With the OS
/// "reduce motion" setting on, nothing moves.
Widget animatedText(Entry entry, String key, Widget child) {
  final type = entry.text(key);
  if (!textAnimationLabels.containsKey(type)) return child;
  // Keyed by the type: choosing another animation starts it over at once.
  return TextEffect(key: ValueKey('text-effect-$type'), type: type, child: child);
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
        case 'flip3d':
          return Opacity(
            opacity: t,
            child: Transform(
              alignment: Alignment.center,
              transform: _perspective()..rotateX(math.pi / 2 * (1 - t)),
              child: child,
            ),
          );
        case 'rotate3d':
          return Opacity(
            opacity: t,
            child: Transform(
              alignment: Alignment.center,
              transform: _perspective()..rotateY(-math.pi / 2 * (1 - t)),
              child: child,
            ),
          );
        case 'spin':
          return Opacity(
            opacity: t,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..rotateZ(2 * math.pi * (1 - t))
                ..scaleByDouble(.3 + .7 * t, .3 + .7 * t, 1, 1),
              child: child,
            ),
          );
        case 'flipLeft':
          return Opacity(
            opacity: t,
            child: Transform(
              alignment: Alignment.centerLeft,
              transform: _perspective()..rotateY(math.pi / 2 * (1 - t)),
              child: child,
            ),
          );
        case 'flipRight':
          return Opacity(
            opacity: t,
            child: Transform(
              alignment: Alignment.centerRight,
              transform: _perspective()..rotateY(-math.pi / 2 * (1 - t)),
              child: child,
            ),
          );
        case 'cube':
          // The new face swings in around the shared edge while sliding across,
          // the way one face of a cube turns into view.
          return Opacity(
            opacity: t,
            child: FractionalTranslation(
              translation: Offset(1 - t, 0),
              child: Transform(
                alignment: Alignment.centerLeft,
                transform: _perspective()..rotateY(-math.pi / 2 * (1 - t)),
                child: child,
              ),
            ),
          );
        case 'pulse':
          return Transform.scale(scale: 1 + .06 * t, alignment: Alignment.centerLeft, child: child);
      }
      return child!;
    },
  );
}
