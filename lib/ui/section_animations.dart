import 'dart:math' as math;

import 'package:flutter/material.dart';


export '../domain/home_animations.dart';

/// How the animation moves, from the start of one play to its end. Used by the live sections and by the admin previews alike.
/// "Entrance" types play once when the part appears; Pulse and Shake repeat; Marquee glides across again and again.
const _repeating = {'pulse', 'shake', 'marquee'};

bool isRepeatingAnimation(String type) => _repeating.contains(type);

/// Plays [type] on [child]. [millis] is one play (speed 1 slow .. 10 fast sets it, see entranceMillis).
class SectionAnimation extends StatefulWidget {
  const SectionAnimation({super.key, required this.type, required this.millis, required this.child});
  final String type;
  final int millis;
  final Widget child;
  @override
  State<SectionAnimation> createState() => _SectionAnimationState();
}

class _SectionAnimationState extends State<SectionAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: _duration);

  Duration get _duration => Duration(
    milliseconds: switch (widget.type) {
      'typewriter' => widget.millis * 2,
      'marquee' => widget.millis * 12,
      'pulse' => widget.millis * 2,
      'shake' => widget.millis * 2,
      _ => widget.millis,
    },
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    controller
      ..duration = _duration
      ..value = 0;
    switch (widget.type) {
      case 'pulse':
        controller.repeat(reverse: true);
      case 'marquee':
        controller.repeat();
      case 'shake':
        // one shake, a pause, again
        controller.repeat(period: _duration + const Duration(seconds: 3));
      default:
        controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant SectionAnimation old) {
    super.didUpdateWidget(old);
    if (old.type != widget.type || old.millis != widget.millis) {
      controller.stop();
      _start();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (context, child) => sectionAnimationFrame(widget.type, controller.value, child!, shakeShare: _duration.inMilliseconds / (_duration.inMilliseconds + 3000)),
  );
}

/// One frame of [type] at progress [t] (0..1) around [child]. Pure, so every animation can be checked frame by frame.
Widget sectionAnimationFrame(String type, double t, Widget child, {double shakeShare = 1}) {
  t = t.clamp(0.0, 1.0);
  final eased = Curves.easeOut.transform(t);
  Widget faded(Widget c) => Opacity(opacity: eased, child: c);
  switch (type) {
    case 'fade':
      return faded(child);
    case 'slide':
      return Transform.translate(offset: Offset(0, (1 - eased) * 24), child: faded(child));
    case 'slideUp':
      return FractionalTranslation(translation: Offset(0, (1 - eased) * .5), child: faded(child));
    case 'slideDown':
      return FractionalTranslation(translation: Offset(0, -(1 - eased) * .5), child: faded(child));
    case 'zoom':
      return Transform.scale(scale: .85 + .15 * eased, child: faded(child));
    case 'zoomIn':
      return Transform.scale(scale: .5 + .5 * eased, child: faded(child));
    case 'zoomOut':
      return Transform.scale(scale: 1.5 - .5 * eased, child: faded(child));
    case 'bounce':
      final b = Curves.bounceOut.transform(t);
      return FractionalTranslation(translation: Offset(0, -(1 - b) * .6), child: Opacity(opacity: math.min(1, t * 4), child: child));
    case 'flip':
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, .0012)
          ..rotateX((1 - eased) * math.pi / 2),
        child: faded(child),
      );
    case 'rotate':
      return Transform.rotate(angle: (1 - eased) * -math.pi / 3, child: Transform.scale(scale: .7 + .3 * eased, child: faded(child)));
    case 'pulse':
      return Transform.scale(scale: 1 + .05 * Curves.easeInOut.transform(t), child: child);
    case 'shake':
      // the shake takes the first part of each round; the rest is rest
      final active = (t / shakeShare).clamp(0.0, 1.0);
      final dx = active >= 1 ? 0.0 : math.sin(active * math.pi * 8) * (1 - active) * 8;
      return Transform.translate(offset: Offset(dx, 0), child: child);
    case 'typewriter':
      // revealed left to right in steps, like typing
      final steps = (t * 24).floor() / 24;
      return ClipRect(child: Align(alignment: Alignment.centerLeft, widthFactor: t >= 1 ? 1 : steps, child: child));
    case 'marquee':
      return LayoutBuilder(
        builder: (context, c) {
          final w = c.hasBoundedWidth ? c.maxWidth : 0.0;
          return ClipRect(child: Transform.translate(offset: Offset(w * (1 - 2 * t), 0), child: child));
        },
      );
    default:
      return child;
  }
}
