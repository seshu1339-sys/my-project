import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'shared.dart';
import 'home_hero_slide.dart';

class PromoCard extends StatelessWidget {
  const PromoCard({super.key, required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(
      clampedNumber(entry, 'radius', 20, 0, 80),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Container(
        decoration: entryDecoration(entry, fallback: const Color(0xffeee6d6)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: entry.number('height', 200).clamp(100, 600),
          ),
          child: Padding(
            padding: EdgeInsets.all(clampedNumber(entry, 'padding', 24, 0, 80)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (entry.text('imageUrl').isNotEmpty)
                  ProductArt(entry, height: 100),
                Text(
                  entry.text('placement') == 'ad'
                      ? 'NEIGHBOURHOOD SPOTLIGHT'
                      : 'CURATED FOR YOU',
                  style: TextStyle(
                    fontSize: entry.number('labelFontSize', 10),
                    color: colorFromHex(
                      entry.text('textColor'),
                      Colors.black87,
                    ),
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  entry.text('name'),
                  style: TextStyle(
                    fontSize: entry.number('fontSize', 25),
                    fontWeight: FontWeight.values.firstWhere(
                      (weight) =>
                          weight.value == entry.number('fontWeight', 700),
                      orElse: () => FontWeight.w700,
                    ),
                    color: colorFromHex(
                      entry.text('textColor'),
                      Colors.black87,
                    ),
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  entry.text('description'),
                  style: TextStyle(
                    color: colorFromHex(
                      entry.text('textColor'),
                      Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Icon(Icons.arrow_forward),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.entries,
    required this.onTap,
    this.reverse = false,
    this.speed = 600,
  });
  final List<Entry> entries;
  final void Function(String) onTap;
  final bool reverse;
  final double speed;
  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final controller = PageController();
  Timer? timer;
  int page = 0;
  @override
  void didUpdateWidget(covariant HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (page >= widget.entries.length) {
      page = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) controller.jumpToPage(0);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(_interval(), (_) {
      if (controller.hasClients &&
          widget.entries.length > 1 &&
          !MediaQuery.of(context).disableAnimations) {
        controller.animateToPage(
          (page + 1) % widget.entries.length,
          duration: Duration(
            milliseconds: widget.speed.clamp(200, 2000).round(),
          ),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Duration _interval() {
    final milliseconds = widget.entries
        .map((entry) => entry.number('animationMs', 6000).round())
        .where((value) => value > 0)
        .fold<int>(6000, (current, value) => current < value ? current : value)
        .clamp(1000, 120000);
    return Duration(milliseconds: milliseconds);
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        SizedBox(
          height:
              360 +
              (MediaQuery.textScalerOf(context).scale(14) / 14 - 1).clamp(
                    0,
                    3,
                  ) *
                  240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: PageView.builder(
              controller: controller,
              itemCount: widget.entries.length,
              reverse: widget.reverse,
              onPageChanged: (v) => setState(() => page = v),
              itemBuilder: (context, i) {
                final p = widget.entries[i];
                return HomeHeroSlide(
                  entry: p,
                  onTap: () => widget.onTap(p.text('target')),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < widget.entries.length; i++)
              IconButton(
                tooltip: 'Show promotion ${i + 1}',
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
                onPressed: () => controller.animateToPage(
                  i,
                  duration: Duration(
                    milliseconds: widget.speed.clamp(200, 2000).round(),
                  ),
                  curve: Curves.easeOut,
                ),
                icon: Icon(
                  i == page ? Icons.circle : Icons.circle_outlined,
                  size: 9,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

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
    final height = widget.height ?? painter.height + widget.padding * 2;
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
                                  ? animation.value
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
                  tooltip: paused ? 'Resume notice' : 'Pause notice',
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
