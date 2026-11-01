import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/ads.dart';
import '../domain/android_home.dart';
import '../domain/android_sizes.dart';
import '../domain/catalog.dart';
import '../domain/right_boxes.dart';
import '../services/ad_tracker.dart';
import 'right_ad_boxes.dart';

/// The ads of the Android home page: small boxes of one size side by side right under the top row, never a half box. They are the
/// same Right Side Ad Boxes the website shows (every box with a photo, same links, same view counting); when there are more than fit,
/// they slide along by themselves, one box at a time, and come round again. Each step waits the seconds of Settings > Right Side Ads
/// ("Seconds each ad stays"), the same setting as the website. How many show at once is Settings > Android App. With fewer ads than
/// boxes, or none, the rest are empty boxes of the same size with the "your ad here" text, so the row is always there.
class AndroidAdsStrip extends StatelessWidget {
  const AndroidAdsStrip({super.key, required this.settings, required this.onTarget, this.tracker, this.town = ''});
  final List<Entry> settings;
  final ValueChanged<String> onTarget;
  final AdsTracker? tracker;
  final String town;

  @override
  Widget build(BuildContext context) {
    final home = AndroidHomeConfig.from(settings);
    final boxes = liveRightBoxes(rightBoxesRecord(settings));
    if (!home.showAds) return const SizedBox.shrink();
    final slots = home.adSlots.clamp(1, 12);
    return _Strip(
      key: ValueKey('android-ads-$slots'),
      boxes: boxes,
      slots: slots,
      seconds: AdsConfig.from(settings).seconds,
      height: AndroidSizes.from(settings).value('ads', 'height'),
      onTarget: onTarget,
      tracker: tracker,
      town: town,
    );
  }
}

class _Strip extends StatefulWidget {
  const _Strip({super.key, required this.boxes, required this.slots, required this.seconds, required this.onTarget, required this.tracker, required this.town, this.height});
  final List<RightBox> boxes;
  final int slots, seconds;
  // The admin's height (Settings > Android App); null = small, by the box's width.
  final double? height;
  final ValueChanged<String> onTarget;
  final AdsTracker? tracker;
  final String town;
  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> {
  static const gap = 4.0;
  late final PageController controller = PageController(viewportFraction: 1 / widget.slots);
  Timer? timer;

  bool get slides => widget.boxes.length > widget.slots;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant _Strip old) {
    super.didUpdateWidget(old);
    if (old.seconds != widget.seconds || old.boxes.length != widget.boxes.length) _arm();
  }

  void _arm() {
    timer?.cancel();
    timer = null;
    if (!slides) return;
    timer = Timer.periodic(Duration(seconds: widget.seconds), (_) {
      if (!mounted || !controller.hasClients || controller.position.isScrollingNotifier.value || MediaQuery.of(context).disableAnimations) return;
      controller.animateToPage((controller.page ?? 0).round() + 1, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Widget _tile(RightBox box) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: gap / 2),
    child: SeenCounter(
      adId: box.countsViews ? box.adId : '',
      tracker: widget.tracker,
      town: widget.town,
      child: Material(
        key: ValueKey('android-ad-${box.number}'),
        color: box.color.isEmpty ? const Color(0xFFE5E7EB) : colorOf(box.color),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: box.hasTarget
              ? () {
                  if (box.countsViews) widget.tracker?.tap(box.adId, town: widget.town);
                  widget.onTarget(box.target);
                }
              : null,
          child: Image.network(box.imageUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity, errorBuilder: (_, error, stack) => const SizedBox.shrink()),
        ),
      ),
    ),
  );

  Widget _empty(int i) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: gap / 2),
    child: Material(
      key: ValueKey('android-ad-empty-$i'),
      color: const Color(0xFFE5E7EB),
      borderRadius: BorderRadius.circular(10),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(rightBoxPlaceholder, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
          ),
        ),
      ),
    ),
  );

  Color colorOf(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return v == null ? const Color(0xFFE5E7EB) : Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final boxWidth = c.maxWidth / widget.slots;
      final height = widget.height ?? (boxWidth * .58).clamp(70.0, 140.0);
      final n = widget.boxes.length;
      return SizedBox(
        key: const ValueKey('android-ads'),
        height: height,
        child: slides
            ? PageView.builder(
                controller: controller,
                padEnds: false,
                // endless: after the last box the first one comes again
                itemBuilder: (context, i) => _tile(widget.boxes[i % n]),
              )
            : Row(children: [
                for (final box in widget.boxes) SizedBox(width: boxWidth, height: height, child: _tile(box)),
                for (var i = n; i < widget.slots; i++) SizedBox(width: boxWidth, height: height, child: _empty(i)),
              ]),
      );
    },
  );
}
