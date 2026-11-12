import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/ads.dart';
import '../domain/android_home.dart';
import '../domain/android_sizes.dart';
import '../domain/catalog.dart';
import '../domain/right_boxes.dart';
import '../services/ad_tracker.dart';
import '../services/server_clock.dart';
import 'ad_box.dart';
import 'right_ad_boxes.dart';

/// The ads of the Android home page: small boxes of one size side by side right under the top row, never a half box. They are the
/// same Right Side Ad Boxes the website shows (every box with a photo, same links, same view counting); when there are more than fit,
/// they slide along by themselves, one box at a time, and come round again. Each step waits the seconds of Settings > Right Side Ads
/// ("Seconds each ad stays"), the same setting as the website. How many show at once is Settings > Android App. With fewer ads than
/// boxes, or none, the rest are empty boxes of the same size with the "your ad here" text, so the row is always there.
class AndroidAdsStrip extends StatefulWidget {
  const AndroidAdsStrip({super.key, required this.settings, required this.onTarget, this.tracker, this.town = '', this.adsAt, this.now, this.showsBox});
  final List<Entry> settings;
  final ValueChanged<String> onTarget;
  final AdsTracker? tracker;
  final String town;

  /// The live ads of the Ads list for this customer (lib/domain/ads.dart liveAds); they follow the boxes with a photo.
  final List<Entry> Function(DateTime now)? adsAt;

  /// The clock; the server's time by default.
  final DateTime Function()? now;

  /// Whether a box's own photo may be shown to this customer (its shop within the admin's km); null: every photo.
  final bool Function(RightBox box)? showsBox;

  @override
  State<AndroidAdsStrip> createState() => _AndroidAdsStripState();
}

class _AndroidAdsStripState extends State<AndroidAdsStrip> {
  Timer? _tick;
  String _signature = '';

  DateTime get _now => (widget.now ?? ServerClock.now)();

  @override
  void initState() {
    super.initState();
    // A box or an ad may start or end at any moment: look again every 5 seconds, no reload needed.
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _items(_now).$3 != _signature) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  (List<RightBox>, List<Entry>, String) _items(DateTime now) {
    final boxes = [for (final b in liveRightBoxes(rightBoxesRecord(widget.settings), now)) if (widget.showsBox?.call(b) ?? true) b];
    final ads = widget.adsAt?.call(now) ?? const <Entry>[];
    return (boxes, ads, [for (final b in boxes) 'b${b.number}${b.imageUrl}', for (final a in ads) 'a${a.id}'].join('|'));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final home = AndroidHomeConfig.from(settings);
    final (boxes, ads, signature) = _items(_now);
    _signature = signature;
    if (!home.showAds) return const SizedBox.shrink();
    final slots = home.adSlots.clamp(1, 12);
    return _Strip(
      key: ValueKey('android-ads-$slots'),
      // The boxes with a photo first (inside their dates), then the live ads of the Ads list.
      boxes: <Object>[...boxes, ...ads],
      slots: slots,
      seconds: AdsConfig.from(settings).seconds,
      height: AndroidSizes.from(settings).value('ads', 'height'),
      onTarget: widget.onTarget,
      tracker: widget.tracker,
      town: widget.town,
      config: AdsConfig.from(settings),
    );
  }
}

class _Strip extends StatefulWidget {
  const _Strip({super.key, required this.boxes, required this.slots, required this.seconds, required this.onTarget, required this.tracker, required this.town, required this.config, this.height});
  // Each one is a RightBox (a box with its photo) or an Entry (an ad of the Ads list).
  final List<Object> boxes;
  final AdsConfig config;
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

  Widget _tile(Object item) {
    if (item is Entry) return _adTile(item);
    return _boxTile(item as RightBox);
  }

  Widget _adTile(Entry ad) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: gap / 2),
    child: SeenCounter(
      adId: ad.id,
      tracker: widget.tracker,
      town: widget.town,
      child: SizedBox.expand(
        key: ValueKey('android-ad-list-${ad.id}'),
        child: AdBox(
          ad: ad,
          config: widget.config,
          mobile: true,
          onTap: (a) {
            widget.tracker?.tap(a.id, town: widget.town);
            final target = adTarget(a);
            if (target.isNotEmpty) widget.onTarget(target);
          },
        ),
      ),
    ),
  );

  Widget _boxTile(RightBox box) => Padding(
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
