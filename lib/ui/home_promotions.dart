import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/analytics.dart';
import '../services/strings.dart';
import 'shared.dart';
import 'home_hero_slide.dart';
import 'layout_settings.dart';

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
            minHeight: clampedNumber(entry, 'height', 200, 100, 1200),
          ),
          child: LayoutBuilder(
            builder: (context, c) => Padding(
              padding: EdgeInsets.all(
                clampedNumber(entry, 'padding', 24, 0, c.maxWidth / 8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (entry.text('imageUrl').isNotEmpty)
                    ProductArt(entry, height: 100),
                  Text(
                    (entry.text('placement') == 'ad'
                            ? 'NEIGHBOURHOOD SPOTLIGHT'
                            : 'CURATED FOR YOU')
                        .tr(context),
                    style: TextStyle(
                      fontSize: clampedNumber(
                        entry,
                        'labelFontSize',
                        10,
                        10,
                        24,
                      ),
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
                      fontSize: clampedNumber(entry, 'fontSize', 25, 10, 40),
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
    this.appearance = const Entry('', {}),
  });
  final List<Entry> entries;
  final Entry appearance;
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
  int pageCount = 1;
  @override
  void didUpdateWidget(covariant HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    timer?.cancel();
    startTimer();
    if (page >= pageCount) {
      page = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) controller.jumpToPage(0);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  void startTimer() {
    timer = Timer.periodic(_interval(), (_) {
      if (controller.hasClients &&
          pageCount > 1 &&
          !MediaQuery.of(context).disableAnimations) {
        controller.animateToPage(
          (page + 1) % pageCount,
          duration: Duration(
            milliseconds: widget.speed.clamp(200, 2000).round(),
          ),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Duration _interval() {
    final configured = widget.appearance.number('animationMs');
    if (configured > 0) {
      return Duration(milliseconds: configured.clamp(1000, 120000).round());
    }
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
    return LayoutBuilder(
      builder: (context, c) {
        final layout = ComponentLayout(
          widget.appearance,
          MediaQuery.sizeOf(context).width,
        );
        final requested = layout.n('visibleCount', 1, 1, 12).round();
        final count = requested.clamp(
          1,
          ((c.maxWidth + layout.gap) / (200 + layout.gap)).floor().clamp(1, 12),
        );
        pageCount = (widget.entries.length / count).ceil();
        if (page >= pageCount) {
          page = 0;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && controller.hasClients) controller.jumpToPage(0);
          });
        }
        final height = layout.height(
          widget.entries.first.number('height', count == 1 ? 300 : 220),
          floor: 120,
        );
        return Column(
          children: [
            SizedBox(
              key: const ValueKey('banner-viewport'),
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(layout.radius),
                child: PageView.builder(
                  controller: controller,
                  itemCount: pageCount,
                  reverse: Directionality.of(context) == TextDirection.rtl
                      ? !widget.reverse
                      : widget.reverse,
                  onPageChanged: (v) => setState(() => page = v),
                  itemBuilder: (context, group) => Row(
                    children: [
                      for (var offset = 0; offset < count; offset++) ...[
                        if (offset > 0) SizedBox(width: layout.gap),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final original =
                                  widget.entries[(group * count + offset) %
                                      widget.entries.length];
                              final entry = Entry(original.id, {
                                ...widget.appearance.data,
                                ...original.data,
                              });
                              void tap() {
                                Analytics.click(entry);
                                widget.onTap(entry.text('target'));
                              }

                              if (count == 1 &&
                                  height >= 300 &&
                                  c.maxWidth >= 700) {
                                return ImpressionOnce(
                                  entry: entry,
                                  child: HomeHeroSlide(
                                    entry: entry,
                                    onTap: tap,
                                  ),
                                );
                              }
                              return SizedBox(
                                height: double.infinity,
                                child: ImpressionOnce(
                                  entry: entry,
                                  child: _CompactBanner(
                                    entry: entry,
                                    onTap: tap,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (pageCount > 1)
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < pageCount; i++)
                    IconButton(
                      tooltip: 'Show promotion {n}'.tr(context, {'n': '${i + 1}'}),
                      onPressed: () => controller.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 400),
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
      },
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

class _CompactBanner extends StatelessWidget {
  const _CompactBanner({required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        decoration: entryDecoration(entry, fallback: const Color(0xffdfebd7)),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(clampedNumber(entry, 'padding', 16, 0, 40)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.text('imageUrl').isNotEmpty)
                  ProductArt(entry, height: 120),
                Text(
                  entry.text('name'),
                  style: sectionTextStyle(
                    entry,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(entry.text('description')),
                const SizedBox(height: 12),
                const Icon(Icons.arrow_forward),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Each promotion owns its playback clock, dimensions and stop timer.
class ScheduledPromo extends StatefulWidget {
  const ScheduledPromo({super.key, required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;
  @override
  State<ScheduledPromo> createState() => _ScheduledPromoState();
}

class _ScheduledPromoState extends State<ScheduledPromo>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(vsync: this);
  Timer? stop;
  bool paused = false;
  double cycle = 1;
  String signature = '';
  Timer? watch;
  bool onScreen = true;

  @override
  void initState() {
    super.initState();
    // An ad scrolled out of view must not keep animating: it wastes battery
    // and produces frames nobody sees. Pause while hidden, resume when shown.
    watch = Timer.periodic(const Duration(milliseconds: 400), (_) => syncVisibility());
  }

  void syncVisibility() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final window = Offset.zero & MediaQuery.sizeOf(context);
    final visible = !(box.localToGlobal(Offset.zero) & box.size).intersect(window).isEmpty;
    if (visible == onScreen) return;
    onScreen = visible;
    if (!visible) {
      animation.stop();
    } else if (!paused && widget.entry.text('scrollEnabled', 'true') == 'true') {
      animation.repeat();
    }
  }

  @override
  void dispose() {
    watch?.cancel();
    stop?.cancel();
    animation.dispose();
    super.dispose();
  }

  void configure(double extent, ComponentLayout layout) {
    final next = '$extent-${widget.entry.data}';
    if (next == signature) return;
    signature = next;
    cycle = extent;
    stop?.cancel();
    animation.stop();
    final enabled = widget.entry.text('scrollEnabled', 'true') == 'true';
    paused = !enabled || widget.entry.text('playback', 'running') != 'running';
    animation.duration = Duration(
      milliseconds: (extent / layout.n('speed', 25, 10, 300) * 1000)
          .round()
          .clamp(1000, 120000),
    );
    if (!paused && onScreen) animation.repeat();
    final seconds = layout.n('stopAfter', 0, 0, 3600);
    if (seconds > 0 && !paused) {
      stop = Timer(Duration(milliseconds: (seconds * 1000).round()), () {
        if (mounted) {
          setState(() {
            paused = true;
            animation.stop();
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final layout = ComponentLayout(
        widget.entry,
        MediaQuery.sizeOf(context).width,
      );
      final height = layout.height(240, floor: 120);
      // The loop distance must equal exactly one card's height: the visible
      // window is also `height` tall, so the two stacked copies always tile
      // it with no seam. Baking `gap` into this distance (as before) made the
      // window briefly show blank space between the outgoing and incoming
      // copy at the midpoint of every cycle — a visible gap flashing through
      // the middle of the box while it scrolled.
      configure(height, layout);
      final moving = widget.entry.text('scrollEnabled', 'true') == 'true';
      final width = layout.width(c.maxWidth, fallback: c.maxWidth, floor: 140);
      final position = widget.entry.text('position', 'start');
      // 'up' (default, unchanged from before) reveals new content from the
      // bottom; 'down' mirrors the same two-copy loop so content instead
      // enters from the top. Any other/blank value falls back to 'up'.
      final scrollsDown = widget.entry.text('direction', 'up') == 'down';
      Widget card() => SizedBox(
        height: height,
        child: SingleChildScrollView(
          child: PromoCard(
            entry: widget.entry,
            onTap: () {
              Analytics.click(widget.entry);
              widget.onTap();
            },
          ),
        ),
      );
      return ImpressionOnce(
        entry: widget.entry,
        child: Align(
          alignment: position == 'end'
              ? Alignment.centerRight
              : position == 'center'
              ? Alignment.center
              : Alignment.centerLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                ClipRect(
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) => Transform.translate(
                      key: ValueKey('promo-motion-${widget.entry.id}'),
                      offset: Offset(
                        0,
                        moving && !MediaQuery.of(context).disableAnimations
                            ? (scrollsDown ? animation.value - 1 : -animation.value) * cycle
                            : 0,
                      ),
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [card(), if (moving) card()],
                        ),
                      ),
                    ),
                  ),
                ),
                if (moving)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      tooltip: (paused ? 'Resume advertisement' : 'Pause advertisement').tr(context),
                      onPressed: () => setState(() {
                        paused = !paused;
                        if (paused) {
                          animation.stop();
                        } else {
                          animation.repeat();
                        }
                      }),
                      icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
