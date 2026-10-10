import 'package:flutter/material.dart';

import '../services/strings.dart';
import 'shared.dart';

class TickerStrip extends StatefulWidget {
  const TickerStrip({
    super.key,
    required this.text,
    this.textColor = Colors.white,
    this.backgroundColor = const Color(0xff174c38),
    this.fontFamily,
    this.fontSize = 12,
    this.fontWeight = FontWeight.normal,
    this.speed = 70,
    this.height,
    this.padding = 9,
    this.reverse = false,
    this.backgroundImage,
    this.brightness = 1,
    this.opacity = 1,
    this.borderColor,
    this.borderWidth = 0,
    this.radius = 0,
    this.playback = 'running',
  });
  final String text;
  final Color textColor, backgroundColor;
  final String? fontFamily;
  final double fontSize, speed, padding;
  final FontWeight fontWeight;
  final bool reverse;
  final String? backgroundImage, borderColor, playback;
  final double brightness, opacity, borderWidth, radius;
  final double? height;
  @override
  State<TickerStrip> createState() => _TickerStripState();
}

class _TickerStripState extends State<TickerStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  bool paused = false;

  @override
  void initState() {
    super.initState();
    animation = AnimationController(vsync: this, duration: _duration())
      ..repeat();
    if (widget.playback != 'running') animation.stop();
    paused = widget.playback == 'paused';
  }

  Duration _duration() => Duration(
    milliseconds: ((widget.text.length * 12 + 64) / widget.speed * 1000)
        .clamp(1000, 120000)
        .round(),
  );

  @override
  void didUpdateWidget(covariant TickerStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.speed != widget.speed ||
        oldWidget.playback != widget.playback) {
      animation.duration = _duration();
      if (widget.playback == 'running') {
        paused = false;
        animation
          ..reset()
          ..repeat();
      } else {
        paused = widget.playback == 'paused';
        animation.stop();
      }
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: widget.textColor,
      fontFamily: widget.fontFamily?.isEmpty == true ? null : widget.fontFamily,
      fontSize: widget.fontSize,
      fontWeight: widget.fontWeight,
      letterSpacing: .6,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    final segmentWidth = painter.width + 64;
    final naturalHeight = painter.height + widget.padding * 2;
    final height = (widget.height ?? naturalHeight).clamp(
      naturalHeight,
      double.infinity,
    );
    final duration = Duration(
      milliseconds: (segmentWidth / widget.speed.clamp(10, 300) * 1000).round(),
    );
    if (animation.duration != duration) {
      animation.duration = duration;
      if (!paused && widget.playback == 'running') animation.repeat();
    }
    painter.dispose();
    final base = widget.backgroundColor;
    final background = Color.lerp(
      Colors.black,
      base,
      widget.brightness.clamp(.2, 2).toDouble().clamp(0, 1),
    )!.withValues(alpha: widget.opacity.clamp(0, 1));
    final decoration = BoxDecoration(
      color: background,
      image: widget.backgroundImage?.isEmpty == true
          ? null
          : widget.backgroundImage == null
          ? null
          : DecorationImage(
              image: NetworkImage(widget.backgroundImage!),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(
                  alpha: 1 - widget.brightness.clamp(.2, 2) / 2,
                ),
                BlendMode.darken,
              ),
            ),
      border: widget.borderWidth > 0
          ? Border.all(
              color: colorFromHex(widget.borderColor ?? '', Colors.transparent),
              width: widget.borderWidth,
            )
          : null,
      borderRadius: BorderRadius.circular(widget.radius),
    );
    return Semantics(
      label: widget.text,
      child: Container(
        height: height,
        decoration: decoration,
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, c) => AnimatedBuilder(
                animation: animation,
                builder: (context, _) => Transform.translate(
                  offset: Offset(
                    MediaQuery.of(context).disableAnimations
                        ? 12
                        : (widget.reverse
                                  ? animation.value - 1
                                  : -animation.value) *
                              segmentWidth,
                    0,
                  ),
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: double.infinity,
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          for (
                            var i = 0;
                            i < (c.maxWidth / segmentWidth).ceil() + 2;
                            i++
                          )
                            SizedBox(
                              width: segmentWidth,
                              child: Text(
                                widget.text,
                                maxLines: 1,
                                style: style,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.playback != 'stopped')
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: IconButton(
                  tooltip: (paused ? 'Resume notice' : 'Pause notice').tr(context),
                  onPressed: () {
                    setState(() {
                      paused = !paused;
                      if (paused) {
                        animation.stop();
                      } else {
                        animation.repeat();
                      }
                    });
                  },
                  icon: Icon(
                    paused ? Icons.play_arrow : Icons.pause,
                    color: widget.textColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
