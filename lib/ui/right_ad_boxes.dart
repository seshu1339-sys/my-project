import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/showcase/showcase_module.dart';
import 'shop_route_map.dart' show ShopStop, showShopRoute;

import '../domain/ads.dart';
import '../domain/catalog.dart';
import '../domain/right_boxes.dart';
import '../services/ad_tracker.dart';
import '../services/server_clock.dart';
import 'ad_box.dart';
import 'ad_visibility.dart';
import 'shared.dart';

/// The Right Side Ad Boxes: every box exactly the same size ([rightBoxHeight] high, the width of the column it is in), one under
/// the other. Customers see only the photo -- no number, no label. A box with a photo shows it only between its own start and end
/// (India time, by the server's clock). Every other box (no photo, ended, not started yet) shows a live ad from the Ads list instead
/// ([adsAt]: approved, inside its dates and its radius, for this customer's place); with more such ads than free boxes they take turns,
/// [AdsConfig.seconds] each. Only when there is nothing to show does a box show the "your ad here" placeholder.
/// A box with a vendor's shop ad (a photo and an ad id) or an ad from the list reports to [tracker] when it has really been seen for a
/// second, and when it is tapped, so the vendor's total views add up (functions/ad-tracking.js).
class RightAdBoxes extends StatefulWidget {
  const RightAdBoxes({super.key, required this.settings, required this.onTarget, this.tracker, this.town = '', this.adsAt, this.now, this.store, this.showcase});

  /// The paid vendors' ad boxes (lib/modules/showcase): one box per paid vendor with the photo they chose, only for customers within
  /// their plan's km, taking turns with the admin's seconds; a tap opens the shop's place and route. [store] gives the customer's
  /// place and the shops; [showcase] the records (from Firestore when null and the store is live).
  final Store? store;
  final Stream<Map<String, ShowcaseEntry>>? showcase;
  final List<Entry> settings;
  final ValueChanged<String> onTarget;
  // Counts the views of the shop ads (null = not counted: the admin's previews, the demo); [town] is the customer's town for the reports.
  final AdsTracker? tracker;
  final String town;

  /// The live ads (lib/domain/ads.dart liveAds) for this customer at a given time; null = boxes only.
  final List<Entry> Function(DateTime now)? adsAt;

  /// The clock; the server's time by default (lib/services/server_clock.dart).
  final DateTime Function()? now;

  @override
  State<RightAdBoxes> createState() => _RightAdBoxesState();
}

/// What one box shows: its own photo, an ad from the Ads list, or the placeholder.
class _Slot {
  const _Slot(this.box, {this.ad, this.vendor});
  final RightBox box;
  final Entry? ad;
  final ShowcaseEntry? vendor;
  bool get ownPhoto => ad == null && vendor == null && box.imageUrl.isNotEmpty;
  String get signature => vendor != null ? 'vendor:${vendor!.vendorId}:${vendor!.photoUrl}' : ad != null ? 'ad:${ad!.id}' : ownPhoto ? 'box:${box.number}:${box.imageUrl}' : 'empty';
}

class _RightAdBoxesState extends State<RightAdBoxes> {
  Timer? _tick;
  int _round = 0, _secondsInRound = 0;
  String _signature = '';

  DateTime get _now => (widget.now ?? ServerClock.now)();
  Map<String, ShowcaseEntry> _reach = const {};
  StreamSubscription<Map<String, ShowcaseEntry>>? _reachSub;

  @override
  void initState() {
    super.initState();
    final source = widget.showcase ?? (widget.store?.live == true ? watchShowcase(widget.store!) : null);
    _reachSub = source?.listen((r) {
      if (mounted) setState(() => _reach = r);
    });
    // Every 5 seconds: a box or an ad may have started or ended (no reload needed), and ads take turns when there are more than boxes.
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _reachSub?.cancel();
    super.dispose();
  }

  /// The paid vendors' boxes this customer may see: within the vendor's plan km of their shop.
  List<ShowcaseEntry> _vendors(DateTime now) {
    final store = widget.store;
    if (store == null) return const [];
    final shops = {for (final s in store.entries('shops')) s.id: s};
    return [
      for (final v in _reach.values)
        if (v.liveAt(now) && v.photoUrl.isNotEmpty)
          if (withinReach(v, lat: store.latitude, lng: store.longitude, shopLat: shops[v.shopId]?.number('latitude'), shopLng: shops[v.shopId]?.number('longitude'))) v,
    ]..sort((a, b) => a.vendorId.compareTo(b.vendorId));
  }

  void _check() {
    if (!mounted) return;
    final config = AdsConfig.from(widget.settings);
    _secondsInRound += 5;
    if (_secondsInRound >= config.seconds) {
      _secondsInRound = 0;
      _round++;
    }
    final next = _slots(_now, config).map((s) => s.signature).join('|');
    if (next != _signature) setState(() {});
  }

  List<_Slot> _slots(DateTime now, AdsConfig config) {
    final boxes = shownRightBoxes(rightBoxesRecord(widget.settings));
    final ads = widget.adsAt?.call(now) ?? const <Entry>[];
    final free = [for (final b in boxes) if (!b.liveAt(now)) b.number];
    // Paid vendors first, one box each, taking turns every [config.seconds]; with as many or fewer vendors than boxes, every other turn
    // has none, so no vendor's box stays on longer than the admin's seconds (owner, 6 Nov 2026). The boxes left go to the ads.
    final vendors = rotationPage<ShowcaseEntry>(_vendors(now), visible: free.length, seconds: config.seconds, now: now);
    final byVendor = <int, ShowcaseEntry>{for (final (i, v) in vendors.indexed) free[i]: v};
    free.removeRange(0, vendors.length);
    final shown = <int, Entry>{};
    if (ads.isNotEmpty && free.isNotEmpty) {
      if (ads.length <= free.length) {
        for (final (i, ad) in ads.indexed) {
          shown[free[i]] = ad;
        }
      } else {
        // More ads than free boxes: each round shows the next set, so every ad gets its turn.
        final start = (_round * free.length) % ads.length;
        for (final (i, number) in free.indexed) {
          shown[number] = ads[(start + i) % ads.length];
        }
      }
    }
    return [
      for (final b in boxes)
        b.liveAt(now) ? _Slot(b) : _Slot(RightBox(b.number, '', b.target, b.color), ad: shown[b.number], vendor: byVendor[b.number]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final config = AdsConfig.from(widget.settings);
    final slots = _slots(_now, config);
    _signature = slots.map((s) => s.signature).join('|');
    if (slots.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('right-ad-boxes'),
      children: [
        for (final slot in slots)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              key: ValueKey('right-box-${slot.box.number}'),
              height: rightBoxHeight,
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: KeyedSubtree(key: ValueKey(slot.signature), child: _content(slot, config)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _content(_Slot slot, AdsConfig config) {
    final box = slot.box;
    final ad = slot.ad;
    final vendor = slot.vendor;
    if (vendor != null) {
      return Material(
        key: ValueKey('right-box-vendor-${vendor.vendorId}'),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // Straight to the shop: its place on the map, address and the way there.
          onTap: () {
            final shop = widget.store?.entries('shops').where((s) => s.id == vendor.shopId).firstOrNull;
            showShopRoute(context, ShopStop.shop(shop, shopId: vendor.shopId));
          },
          child: Image.network(vendor.photoUrl, fit: BoxFit.cover, width: double.infinity, height: rightBoxHeight, errorBuilder: (_, error, stack) => const _Placeholder()),
        ),
      );
    }
    if (ad != null) {
      return SeenCounter(
        adId: ad.id,
        tracker: widget.tracker,
        town: widget.town,
        child: SizedBox.expand(
          key: ValueKey('right-box-ad-${ad.id}'),
          child: AdBox(
            ad: ad,
            config: config,
            onTap: (a) {
              widget.tracker?.tap(a.id, town: widget.town);
              final target = adTarget(a);
              if (target.isNotEmpty) widget.onTarget(target);
            },
          ),
        ),
      );
    }
    return SeenCounter(
      adId: box.countsViews ? box.adId : '',
      tracker: widget.tracker,
      town: widget.town,
      child: Material(
        color: box.imageUrl.isEmpty ? const Color(0xFFE5E7EB) : box.color.isEmpty ? Colors.white : colorFromHex(box.color, Colors.white),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: box.hasTarget
              ? () {
                  if (box.countsViews) widget.tracker?.tap(box.adId, town: widget.town);
                  widget.onTarget(box.target);
                }
              : null,
          child: box.imageUrl.isEmpty
              ? const _Placeholder()
              : Image.network(
                  box.imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: rightBoxHeight,
                  errorBuilder: (_, error, stack) => const _Placeholder(),
                ),
        ),
      ),
    );
  }
}

/// Reports one view of [adId] once the box has been on screen for a second (the tracker and the server drop repeats within a minute).
/// Does nothing for a box without a shop ad or without a tracker.
class SeenCounter extends StatefulWidget {
  const SeenCounter({super.key, required this.adId, required this.tracker, required this.town, required this.child});
  final String adId, town;
  final AdsTracker? tracker;
  final Widget child;
  @override
  State<SeenCounter> createState() => SeenCounterState();
}

class SeenCounterState extends State<SeenCounter> {
  Timer? _watch;
  int _visibleMs = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(SeenCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another ad in the box (the admin linked another vendor): its own view.
    if (oldWidget.adId != widget.adId || oldWidget.tracker != widget.tracker) _start();
  }

  void _start() {
    _watch?.cancel();
    _watch = null;
    _visibleMs = 0;
    if (widget.adId.isNotEmpty && widget.tracker != null) _watch = Timer.periodic(const Duration(milliseconds: 500), (_) => _look());
  }

  void _look() {
    if (mounted && adMostlyOnScreen(context)) _visibleMs += 500;
    if (_visibleMs >= 1000) {
      _watch?.cancel();
      _watch = null;
      widget.tracker?.view(widget.adId, town: widget.town);
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        rightBoxPlaceholder,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
      ),
    ),
  );
}
