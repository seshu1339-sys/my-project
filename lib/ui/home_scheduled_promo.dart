import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/analytics.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'home_impression_once.dart';
import 'home_promo_card.dart';
import 'layout_settings.dart';

/// Each promotion owns its playback clock, dimensions and stop timer.
class ScheduledPromo extends StatefulWidget {
  const ScheduledPromo({super.key, required this.entry, required this.onTap, this.heightOverride});
  final Entry entry;
  final VoidCallback onTap;
  // When set, replaces the usual admin-configured/responsive height
  // computation outright (used by the ad rail to force every ad to the
  // exact same pixel height, bypassing the per-entry 'height' field and
  // the component-layout scale factor entirely, so there's a single
  // source of truth for the number instead of two formulas that can
  // disagree).
  final double? heightOverride;
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
    } else if (!paused && widget.entry.text('scrollEnabled', 'false') == 'true') {
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
    final enabled = widget.entry.text('scrollEnabled', 'false') == 'true';
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
      final height = widget.heightOverride ?? layout.height(240, floor: 120);
      // The loop distance must equal exactly one card's height: the visible
      // window is also `height` tall, so the two stacked copies always tile
      // it with no seam. Baking `gap` into this distance (as before) made the
      // window briefly show blank space between the outgoing and incoming
      // copy at the midpoint of every cycle — a visible gap flashing through
      // the middle of the box while it scrolled.
      configure(height, layout);
      final moving = widget.entry.text('scrollEnabled', 'false') == 'true';
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
            exactHeight: widget.heightOverride,
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

/// Pages through the SAME merged ad/box entries the desktop rail builds (see
/// `mergedPromoEntries` in wireframe_home.dart), one unmodified
/// [ScheduledPromo] per page, auto-advancing the same way [HeroCarousel]
/// already does. ScheduledPromo itself is untouched — this only changes how
/// many are shown at once and how the viewer moves between them, so every
/// per-entry admin control (scrollEnabled/playback/speed/stopAfter/
/// direction/position) keeps working exactly as it does in the desktop rail.
/// Zero new Firestore reads: `entries` is the same list already fetched for
/// the rail.
class ScheduledPromoCarousel extends StatefulWidget {
  const ScheduledPromoCarousel({
    super.key,
    required this.entries,
    required this.appearance,
    required this.onTap,
  });
  final List<Entry> entries;
  final Entry appearance;
  final void Function(String target) onTap;
  @override
  State<ScheduledPromoCarousel> createState() => _ScheduledPromoCarouselState();
}

class _ScheduledPromoCarouselState extends State<ScheduledPromoCarousel> {
  final controller = PageController();
  Timer? timer;
  int page = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant ScheduledPromoCarousel old) {
    super.didUpdateWidget(old);
    if (old.entries.length != widget.entries.length && page >= widget.entries.length) {
      page = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) controller.jumpToPage(0);
      });
    }
    _start();
  }

  void _start() {
    timer?.cancel();
    if (widget.entries.length < 2) return;
    timer = Timer.periodic(_interval(), (_) {
      if (controller.hasClients && !MediaQuery.of(context).disableAnimations) {
        controller.animateToPage(
          (page + 1) % widget.entries.length,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Duration _interval() {
    final configured = widget.appearance.number('animationMs');
    if (configured > 0) {
      return Duration(milliseconds: configured.clamp(2000, 120000).round());
    }
    final milliseconds = widget.entries
        .map((entry) => entry.number('animationMs', 6000).round())
        .where((value) => value > 0)
        .fold<int>(6000, (current, value) => current < value ? current : value)
        .clamp(2000, 120000);
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
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final layout = ComponentLayout(widget.appearance, MediaQuery.sizeOf(context).width);
    final height = layout.height(200, floor: 140);
    return Column(
      children: [
        SizedBox(
          key: const ValueKey('ad-carousel-viewport'),
          height: height,
          child: PageView.builder(
            controller: controller,
            itemCount: widget.entries.length,
            onPageChanged: (v) => setState(() => page = v),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ScheduledPromo(
                entry: widget.entries[i],
                onTap: () => widget.onTap(widget.entries[i].text('target')),
              ),
            ),
          ),
        ),
        if (widget.entries.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                for (var i = 0; i < widget.entries.length; i++)
                  Icon(
                    i == page ? Icons.circle : Icons.circle_outlined,
                    size: 7,
                    color: AppTokens.primary,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
