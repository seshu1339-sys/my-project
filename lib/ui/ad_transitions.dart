import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One frame of a change from the ad on screen ([outgoing]) to the next one ([incoming]); [t] runs from 0 (all outgoing) to 1 (all incoming).
/// Every slot uses this, so every animation looks the same in every ad box.
Widget adTransitionFrame(String type, double t, Widget outgoing, Widget incoming) {
  t = t.clamp(0.0, 1.0);
  switch (type) {
    case 'slideUp':
      return ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          FractionalTranslation(translation: Offset(0, -t), child: outgoing),
          FractionalTranslation(translation: Offset(0, 1 - t), child: incoming),
        ]),
      );
    case 'slideLeft':
      return ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          FractionalTranslation(translation: Offset(-t, 0), child: outgoing),
          FractionalTranslation(translation: Offset(1 - t, 0), child: incoming),
        ]),
      );
    case 'flip':
      final first = t < .5;
      final angle = first ? t * math.pi : (t - 1) * math.pi;
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, .0012)
          ..rotateY(angle),
        child: first ? outgoing : incoming,
      );
    case 'zoom':
      return Stack(fit: StackFit.expand, children: [
        Opacity(opacity: 1 - t, child: Transform.scale(scale: 1 + .2 * t, child: outgoing)),
        Opacity(opacity: t, child: Transform.scale(scale: .8 + .2 * t, child: incoming)),
      ]);
    case 'cube':
      // Two faces of a cube turning a quarter turn: the old face swings away to the left, the new one swings in from the right.
      return LayoutBuilder(
        builder: (context, c) => ClipRect(
          child: Stack(fit: StackFit.expand, children: [
            Transform(
              alignment: Alignment.centerRight,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0015)
                ..translateByDouble(-c.maxWidth * t, 0, 0, 1)
                ..rotateY(t * math.pi / 2),
              child: outgoing,
            ),
            Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0015)
                ..translateByDouble(c.maxWidth * (1 - t), 0, 0, 1)
                ..rotateY(-(1 - t) * math.pi / 2),
              child: incoming,
            ),
          ]),
        ),
      );
    default: // fade
      return Stack(fit: StackFit.expand, children: [
        Opacity(opacity: 1 - t, child: outgoing),
        Opacity(opacity: t, child: incoming),
      ]);
  }
}
