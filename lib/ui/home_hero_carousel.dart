import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/analytics.dart';
import '../services/strings.dart';
import 'home_hero_slide.dart';
import 'home_impression_once.dart';
import 'home_promo_card.dart';
import 'home_rotating_pages.dart';
import 'layout_settings.dart';

class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.entries,
    required this.onTap,
    this.reverse = false,
    this.speed = 600,
    this.appearance = const Entry('', {}),
    this.boxBuilder,
  });
  final List<Entry> entries;
  final Entry appearance;
  /// Draws a box's inside instead of the promotion's own text (Today's Offers item offers, home_today_offers.dart): the box keeps
  /// its size, place and movement. [index] is the entry's place in [entries].
  final Widget Function(BuildContext context, Entry entry, int index)? boxBuilder;
  final void Function(String) onTap;
  final bool reverse;
  final double speed;
  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final controller = PageController();
  final rotation = RotatingPagesController();
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
    rotation.dispose();
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
        // 150px (not 200px) is the minimum width a single offer card is
        // allowed to shrink to when fitting `requested` cards into the
        // available width -- lets an admin-requested visibleCount of 6
        // actually show 6 at once on a typical desktop width instead of
        // being silently clamped down to however many fit at 200px each.
        final count = requested.clamp(
          1,
          ((c.maxWidth + layout.gap) / (150 + layout.gap)).floor().clamp(1, 12),
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
        Widget slide(int entryIndex) {
          final original = widget.entries[entryIndex % widget.entries.length];
          final entry = Entry(original.id, {
            ...widget.appearance.data,
            ...original.data,
          });
          if (widget.boxBuilder != null) {
            return SizedBox(height: double.infinity, child: widget.boxBuilder!(context, entry, entryIndex % widget.entries.length));
          }
          void tap() {
            Analytics.click(entry);
            widget.onTap(entry.text('target'));
          }

          if (count == 1 && height >= 300 && c.maxWidth >= 700) {
            return ImpressionOnce(
              entry: entry,
              child: HomeHeroSlide(entry: entry, onTap: tap),
            );
          }
          return SizedBox(
            height: double.infinity,
            child: ImpressionOnce(
              entry: entry,
              child: CompactBanner(entry: entry, onTap: tap),
            ),
          );
        }

        // An admin-chosen animation (Settings -> Today's Offers) replaces the
        // plain page swipe; with none chosen the PageView below is unchanged.
        final motion = PromoMotion.from(
          widget.appearance,
          defaultIntervalMs: 6000,
        );
        if (motion != null) {
          final carousel = motion.type == PromoAnimation.carousel;
          final pages = carousel ? widget.entries.length : pageCount;
          return Column(
            children: [
              SizedBox(
                key: const ValueKey('banner-viewport'),
                height: height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(layout.radius),
                  child: RotatingPages(
                    key: ValueKey('offers-rotation-${motion.type.name}'),
                    motion: motion,
                    pageCount: pages,
                    slotsPerView: count,
                    reverse: widget.reverse,
                    controller: rotation,
                    pageBuilder: (context, index) => carousel
                        ? Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: layout.gap / 2,
                            ),
                            child: slide(index),
                          )
                        : Row(
                            children: [
                              for (var offset = 0; offset < count; offset++) ...[
                                if (offset > 0) SizedBox(width: layout.gap),
                                Expanded(child: slide(index * count + offset)),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
              RotatingDots(
                controller: rotation,
                count: pages,
                tooltipFor: (i) =>
                    'Show promotion {n}'.tr(context, {'n': '${i + 1}'}),
              ),
            ],
          );
        }
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
                              if (widget.boxBuilder != null) {
                                return SizedBox(
                                  height: double.infinity,
                                  child: widget.boxBuilder!(context, entry, (group * count + offset) % widget.entries.length),
                                );
                              }
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
                                  child: CompactBanner(
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
