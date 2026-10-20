import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'design_tokens.dart';

/// The seven transitions an admin can pick (per group) for Today's Offers
/// and for the ads. The stored `animationType` value is the enum name; blank
/// or unknown means "not chosen" and the group keeps its original behavior.
enum PromoAnimation { slide, fade, flip, cube, zoom, bounce, carousel }

const promoAnimationLabels = <String, String>{
  'slide': 'Slide (left/right or up/down)',
  'fade': 'Fade',
  'flip': 'Flip',
  'cube': 'Rotate / 3D cube',
  'zoom': 'Zoom',
  'bounce': 'Bounce',
  'carousel': 'Carousel (centre bigger, sides smaller)',
};

/// One group's animation settings, read from its `settings/section_KEY` doc
/// (`animationType`, `animationSpeed`, `animationMs`, `pauseOnTouch`).
class PromoMotion {
  const PromoMotion({
    required this.type,
    required this.transition,
    required this.interval,
    required this.pauseOnTouch,
  });
  final PromoAnimation type;
  // How long one change takes.
  final Duration transition;
  // How long each page stays before the next change starts.
  final Duration interval;
  final bool pauseOnTouch;

  /// Null when the admin hasn't chosen an animation type -- callers then
  /// render exactly what they always did.
  static PromoMotion? from(Entry settings, {int defaultIntervalMs = 5000}) {
    final name = settings.text('animationType');
    final type = PromoAnimation.values
        .where((value) => value.name == name)
        .firstOrNull;
    if (type == null) return null;
    final configured = settings.number('animationMs');
    final interval = (configured > 0 ? configured : defaultIntervalMs)
        .clamp(1500, 120000)
        .round();
    // Speed 1 (slow) .. 10 (fast); a change never takes longer than most of
    // the time the page is meant to stay.
    final speed = settings.number('animationSpeed', 5).clamp(1, 10);
    final transition = (1700 - 150 * speed).round().clamp(
      200,
      (interval * .8).round(),
    );
    return PromoMotion(
      type: type,
      transition: Duration(milliseconds: transition),
      interval: Duration(milliseconds: interval),
      pauseOnTouch: settings.text('pauseOnTouch', 'true') != 'false',
    );
  }
}

/// Share of the viewport one carousel item takes (the rest shows its
/// neighbours); callers size the viewport as slot size / this fraction.
double carouselFraction(int slots) =>
    slots <= 1 ? .6 : (1 / slots).clamp(.18, .6).toDouble();

/// Lets a caller read which page is showing (for dots) and jump to one.
class RotatingPagesController {
  final ValueNotifier<int> page = ValueNotifier(0);
  void Function(int)? _goTo;
  void goTo(int index) => _goTo?.call(index);
  void dispose() => page.dispose();
}

/// Cycles through [pageCount] pages forever, changing page every
/// `motion.interval` with the chosen transition. The widget fills whatever
/// bounded box its parent gives it and every page is laid out at exactly
/// that size, so boxes are the same size before, during and after any
/// transition; the only thing that moves is paint (translate/fade/scale/
/// rotate), and it is all clipped to the box.
class RotatingPages extends StatefulWidget {
  const RotatingPages({
    super.key,
    required this.motion,
    required this.pageCount,
    required this.pageBuilder,
    this.axis = Axis.horizontal,
    this.reverse = false,
    this.slotsPerView = 1,
    this.controller,
  });
  final PromoMotion motion;
  final int pageCount;
  final Widget Function(BuildContext context, int index) pageBuilder;
  final Axis axis;
  // Flips the direction of the slide-like transitions.
  final bool reverse;
  // Carousel type only: how many items fit across the viewport (each one is
  // a "page"); the centre one is drawn largest.
  final int slotsPerView;
  final RotatingPagesController? controller;
  @override
  State<RotatingPages> createState() => _RotatingPagesState();
}

class _RotatingPagesState extends State<RotatingPages>
    with SingleTickerProviderStateMixin {
  late final AnimationController change = AnimationController(vsync: this);
  Timer? timer;
  PageController? pager;
  int current = 0;
  int? target;
  bool hovering = false, touching = false;
  Timer? releaseTimer;

  bool get isCarousel => widget.motion.type == PromoAnimation.carousel;
  bool get paused => widget.motion.pauseOnTouch && (hovering || touching);

  @override
  void initState() {
    super.initState();
    change.addStatusListener((status) {
      if (status == AnimationStatus.completed && target != null && mounted) {
        setState(() {
          current = target!;
          target = null;
        });
        widget.controller?.page.value = current;
      }
    });
    widget.controller?._goTo = goTo;
    _restart();
  }

  @override
  void didUpdateWidget(covariant RotatingPages old) {
    super.didUpdateWidget(old);
    widget.controller?._goTo = goTo;
    if (current >= widget.pageCount) {
      current = 0;
      target = null;
      change.stop();
    }
    final carouselChanged =
        old.motion.type != widget.motion.type ||
        old.slotsPerView != widget.slotsPerView ||
        old.axis != widget.axis;
    if (carouselChanged) {
      pager?.dispose();
      pager = null;
      target = null;
      change.stop();
    }
    if (old.motion.interval != widget.motion.interval ||
        old.motion.type != widget.motion.type) {
      _restart();
    }
  }

  void _restart() {
    timer?.cancel();
    timer = Timer.periodic(widget.motion.interval, (_) => _tick());
  }

  void _tick() {
    if (!mounted || paused || widget.pageCount < 2) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    if (isCarousel) {
      final controller = pager;
      if (controller != null && controller.hasClients) {
        controller.nextPage(
          duration: widget.motion.transition,
          curve: Curves.easeInOut,
        );
      }
    } else {
      goTo((current + 1) % widget.pageCount);
    }
  }

  void goTo(int index) {
    if (!mounted || widget.pageCount < 2) return;
    final wanted = index % widget.pageCount;
    if (isCarousel) {
      final controller = pager;
      if (controller == null || !controller.hasClients) return;
      final base = controller.page?.round() ?? 0;
      final ahead = (wanted - base % widget.pageCount) % widget.pageCount;
      controller.animateToPage(
        base + ahead,
        duration: widget.motion.transition,
        curve: Curves.easeInOut,
      );
      return;
    }
    if (target != null) {
      // A change is still running: finish it first, then go where asked.
      change.stop();
      current = target!;
      target = null;
    }
    if (wanted == current) return;
    setState(() => target = wanted);
    change.duration = widget.motion.transition;
    change.forward(from: 0);
  }

  void _setTouching(bool value) {
    releaseTimer?.cancel();
    if (value) {
      touching = true;
    } else {
      // Keep the page still a moment after the finger lifts so a tap on a
      // box isn't pulled out from under it by the next change.
      releaseTimer = Timer(const Duration(milliseconds: 1500), () {
        touching = false;
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    releaseTimer?.cancel();
    pager?.dispose();
    change.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => hovering = true,
    onExit: (_) => hovering = false,
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setTouching(true),
      onPointerUp: (_) => _setTouching(false),
      onPointerCancel: (_) => _setTouching(false),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, c) => isCarousel
              ? _carousel(context)
              : _transition(context, c.biggest),
        ),
      ),
    ),
  );

  // ---- carousel: centre item biggest, neighbours smaller -----------------

  Widget _carousel(BuildContext context) {
    final count = widget.pageCount;
    final slots = widget.slotsPerView.clamp(1, 12);
    final fraction = carouselFraction(slots);
    if (pager == null) {
      pager = PageController(
        viewportFraction: fraction,
        initialPage: count * 500,
      )..addListener(_onPagerMoved);
      // The pager only knows its position after its first layout; redraw once
      // then so the neighbours start smaller instead of waiting for a move.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    return PageView.builder(
      key: ValueKey('carousel-$slots-${widget.axis.name}'),
      controller: pager,
      scrollDirection: widget.axis,
      reverse: widget.reverse && widget.axis == Axis.horizontal,
      itemBuilder: (context, index) => AnimatedBuilder(
        animation: pager!,
        builder: (context, child) {
          final position = pager!.hasClients && pager!.position.haveDimensions
              ? pager!.page ?? index.toDouble()
              : index.toDouble();
          final distance = (position - index).abs().clamp(0.0, 1.0);
          return Transform.scale(
            scale: 1 - .18 * distance,
            child: Opacity(opacity: 1 - .3 * distance, child: child),
          );
        },
        child: widget.pageBuilder(context, index % count),
      ),
    );
  }

  void _onPagerMoved() {
    final controller = pager;
    if (controller == null || !controller.hasClients) return;
    final page = controller.page;
    if (page == null || widget.pageCount == 0) return;
    final shown = page.round() % widget.pageCount;
    if (widget.controller?.page.value != shown) {
      widget.controller?.page.value = shown;
    }
  }

  // ---- slide / fade / flip / cube / zoom / bounce -------------------------

  Widget _transition(BuildContext context, Size size) {
    Widget page(int index) => SizedBox.fromSize(
      size: size,
      child: KeyedSubtree(
        key: ValueKey('rotating-page-$index'),
        child: widget.pageBuilder(context, index),
      ),
    );
    final to = target;
    if (to == null) return page(current);
    return AnimatedBuilder(
      animation: change,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(change.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            _move(page(current), t, size, incoming: false),
            _move(page(to), t, size, incoming: true),
          ],
        );
      },
    );
  }

  Widget _move(
    Widget child,
    double t,
    Size size, {
    required bool incoming,
  }) {
    final horizontal = widget.axis == Axis.horizontal;
    final extent = horizontal ? size.width : size.height;
    final sign = widget.reverse ? -1.0 : 1.0;
    Offset slide(double fraction) =>
        horizontal ? Offset(fraction * extent, 0) : Offset(0, fraction * extent);
    switch (widget.motion.type) {
      case PromoAnimation.slide:
        return Transform.translate(
          offset: slide(incoming ? sign * (1 - t) : -sign * t),
          child: child,
        );
      case PromoAnimation.bounce:
        // The new page lands with a bounce; the old one just leaves.
        final landed = Curves.bounceOut.transform(change.value);
        return Transform.translate(
          offset: slide(incoming ? sign * (1 - landed) : -sign * t),
          child: child,
        );
      case PromoAnimation.fade:
        return Opacity(opacity: incoming ? t : 1 - t, child: child);
      case PromoAnimation.zoom:
        return Opacity(
          opacity: incoming ? t : 1 - t,
          child: Transform.scale(
            scale: incoming ? .65 + .35 * t : 1 + .35 * t,
            child: child,
          ),
        );
      case PromoAnimation.flip:
        // Old page turns edge-on in the first half, the new one turns in.
        if (incoming ? t < .5 : t >= .5) return const SizedBox.shrink();
        final angle = incoming ? -math.pi * (1 - t) : math.pi * t;
        return Transform(
          alignment: Alignment.center,
          transform: _perspective(extent)
            ..rotateY(horizontal ? angle : 0)
            ..rotateX(horizontal ? 0 : angle),
          child: child,
        );
      case PromoAnimation.cube:
        // Two faces of a cube turning about its vertical (or horizontal) edge.
        final angle = incoming
            ? sign * (1 - t) * math.pi / 2
            : -sign * t * math.pi / 2;
        final depth = extent / 2;
        return Transform(
          alignment: Alignment.center,
          transform: _perspective(extent)
            ..translateByDouble(0, 0, -depth, 1)
            ..rotateY(horizontal ? angle : 0)
            ..rotateX(horizontal ? 0 : -angle)
            ..translateByDouble(0, 0, depth, 1),
          child: child,
        );
      case PromoAnimation.carousel:
        return child;
    }
  }

  Matrix4 _perspective(double extent) =>
      Matrix4.identity()..setEntry(3, 2, .5 / math.max(extent, 1));
}

/// Page dots for a [RotatingPages]; tapping one jumps to that page.
class RotatingDots extends StatelessWidget {
  const RotatingDots({
    super.key,
    required this.controller,
    required this.count,
    this.tooltipFor,
  });
  final RotatingPagesController controller;
  final int count;
  final String Function(int index)? tooltipFor;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: controller.page,
      builder: (context, page, _) => Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            IconButton(
              tooltip: tooltipFor?.call(i),
              onPressed: () => controller.goTo(i),
              icon: Icon(
                i == page % count ? Icons.circle : Icons.circle_outlined,
                size: 9,
                color: AppTokens.primary,
              ),
            ),
        ],
      ),
    );
  }
}
