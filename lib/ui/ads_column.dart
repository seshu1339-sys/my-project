import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/ads.dart';
import '../domain/catalog.dart';
import '../services/ad_tracker.dart';
import 'ad_box.dart';
import 'ad_transitions.dart';

/// Which ad each slot shows. All slots read one round of the rotation ([adCycle]); a slot never shows an ad another slot is already
/// showing, so the visible ads are always different from each other.
class AdsRotation extends ChangeNotifier {
  AdsRotation(this.cycle, int slots) {
    final ids = <String>{};
    var at = 0;
    for (var slot = 0; slot < slots; slot++) {
      while (at < cycle.length && ids.contains(cycle[at].id)) {
        at++;
      }
      if (at >= cycle.length) break;
      index.add(at);
      ids.add(cycle[at].id);
    }
  }

  final List<Entry> cycle;
  final List<int> index = [];

  /// How many slots can be filled with different ads.
  int get visibleSlots => index.length;

  Entry current(int slot) => cycle[index[slot]];

  /// The distinct ads, in the order they first appear in the cycle (for the dots).
  List<Entry> get distinctAds {
    final seen = <String>{};
    return [for (final ad in cycle) if (seen.add(ad.id)) ad];
  }

  bool _shownElsewhere(String id, int slot) => [for (var i = 0; i < index.length; i++) if (i != slot) cycle[index[i]].id].contains(id);

  /// Moves a slot on to the next (or, with [back], the previous) ad that no other slot is showing. Returns whether it changed.
  bool step(int slot, {bool back = false}) {
    final here = cycle[index[slot]].id;
    for (var n = 1; n < cycle.length; n++) {
      final j = ((index[slot] + (back ? -n : n)) % cycle.length + cycle.length) % cycle.length;
      final id = cycle[j].id;
      if (id != here && !_shownElsewhere(id, slot)) {
        index[slot] = j;
        notifyListeners();
        return true;
      }
    }
    return false;
  }
}

/// The height of one ad box so that [slots] boxes (and their gaps) fit the visible screen height: never taller than the admin's box height,
/// never so small the ad is unreadable.
double adBoxHeight(AdsConfig config, double screenHeight, int slots) {
  if (!config.fitToScreen) return config.boxHeight;
  final budget = screenHeight - 200; // the header and some breathing room above and below
  final fit = (budget - config.gap * (slots - 1)) / slots;
  return math.max(90.0, math.min(config.boxHeight, fit));
}

typedef AdTap = void Function(Entry ad);

/// The right-hand column on a wide screen: a fixed number of equal ad boxes, always fully on screen, each changing ad on its own beat
/// (staggered). Scrolling or dragging over the column switches to a list of every live ad; a few seconds after the last touch it goes
/// back to the automatic boxes.
class AdsColumn extends StatefulWidget {
  const AdsColumn({super.key, required this.ads, required this.config, required this.onTap, this.screenHeight, this.tracker, this.town = ''});
  final List<Entry> ads;
  final AdsConfig config;
  final AdTap onTap;
  final double? screenHeight;
  // Counts genuine views (null = not counted, e.g. the admin's previews); [town] is the customer's town for the reports.
  final AdsTracker? tracker;
  final String town;

  @override
  State<AdsColumn> createState() => _AdsColumnState();
}

class _AdsColumnState extends State<AdsColumn> {
  late AdsRotation rotation = _build();
  bool browsing = false;
  Timer? _idle;

  AdsRotation _build() => AdsRotation(adCycle(widget.ads), widget.config.desktopSlots);

  @override
  void didUpdateWidget(covariant AdsColumn old) {
    super.didUpdateWidget(old);
    final ids = widget.ads.map((a) => '${a.id}/${adRounds(a)}').join(',');
    final before = old.ads.map((a) => '${a.id}/${adRounds(a)}').join(',');
    if (ids != before || old.config.desktopSlots != widget.config.desktopSlots) {
      rotation.dispose();
      rotation = _build();
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    rotation.dispose();
    super.dispose();
  }

  void _touched() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => browsing = false);
    });
    if (!browsing) setState(() => browsing = true);
  }

  @override
  Widget build(BuildContext context) {
    final slots = rotation.visibleSlots;
    if (slots == 0) return const SizedBox.shrink();
    final config = widget.config;
    final height = adBoxHeight(config, widget.screenHeight ?? MediaQuery.sizeOf(context).height, slots);
    final total = slots * height + (slots - 1) * config.gap;
    final all = rotation.distinctAds;
    return Listener(
      key: const ValueKey('ads-column'),
      onPointerSignal: (_) => _touched(),
      child: SizedBox(
        height: total,
        child: browsing
            ? NotificationListener<ScrollNotification>(
                onNotification: (_) {
                  _touched();
                  return false;
                },
                child: ListView.separated(
                  key: const ValueKey('ads-browse'),
                  padding: EdgeInsets.zero,
                  itemCount: all.length,
                  separatorBuilder: (_, _) => SizedBox(height: config.gap),
                  itemBuilder: (context, i) => SizedBox(height: height, child: AdBox(ad: all[i], config: config, onTap: widget.onTap)),
                ),
              )
            : Column(
                children: [
                  for (var slot = 0; slot < slots; slot++) ...[
                    if (slot > 0) SizedBox(height: config.gap),
                    SizedBox(
                      height: height,
                      child: AdSlot(key: ValueKey('ad-slot-$slot'), rotation: rotation, slot: slot, slots: slots, config: config, onTap: widget.onTap, tracker: widget.tracker, town: widget.town),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// The phone / customer-app version: one ad at a time, swipe left or right (or wait) to change, with dots. It changes with the same
/// animation as every other ad box.
class AdsPager extends StatefulWidget {
  const AdsPager({super.key, required this.ads, required this.config, required this.onTap, this.height, this.tracker, this.town = ''});
  final List<Entry> ads;
  final AdsConfig config;
  final AdTap onTap;
  final double? height;
  final AdsTracker? tracker;
  final String town;
  @override
  State<AdsPager> createState() => _AdsPagerState();
}

class _AdsPagerState extends State<AdsPager> {
  late AdsRotation rotation = AdsRotation(adCycle(widget.ads), widget.config.mobileSlots);

  @override
  void didUpdateWidget(covariant AdsPager old) {
    super.didUpdateWidget(old);
    final ids = widget.ads.map((a) => '${a.id}/${adRounds(a)}').join(',');
    final before = old.ads.map((a) => '${a.id}/${adRounds(a)}').join(',');
    if (ids != before || old.config.mobileSlots != widget.config.mobileSlots) {
      rotation.dispose();
      rotation = AdsRotation(adCycle(widget.ads), widget.config.mobileSlots);
    }
  }

  @override
  void dispose() {
    rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slots = rotation.visibleSlots;
    if (slots == 0) return const SizedBox.shrink();
    final config = widget.config;
    final width = MediaQuery.sizeOf(context).width;
    final height = widget.height ?? math.min(config.boxHeight, math.max(130.0, width * .5));
    return Column(
      key: const ValueKey('ads-pager'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var slot = 0; slot < slots; slot++) ...[
          if (slot > 0) SizedBox(height: config.gap),
          SizedBox(
            height: height,
            child: AdSlot(key: ValueKey('ad-slot-$slot'), rotation: rotation, slot: slot, slots: slots, config: config, onTap: widget.onTap, swipe: true, mobile: true, tracker: widget.tracker, town: widget.town),
          ),
        ],
        const SizedBox(height: 6),
        ListenableBuilder(
          listenable: rotation,
          builder: (context, _) {
            final all = rotation.distinctAds;
            final shown = rotation.current(0).id;
            return Row(
              key: const ValueKey('ads-dots'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final ad in all)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: ad.id == shown ? Theme.of(context).colorScheme.primary : Colors.black26),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One ad box that changes ad by itself (after the ad's own seconds, starting at its own offset so the boxes do not all change at once),
/// pauses while touched / hovered, and can be swiped.
class AdSlot extends StatefulWidget {
  const AdSlot({
    super.key,
    required this.rotation,
    required this.slot,
    required this.slots,
    required this.config,
    required this.onTap,
    this.swipe = false,
    this.mobile = false,
    this.tracker,
    this.town = '',
  });
  final AdsRotation rotation;
  final int slot, slots;
  final AdsConfig config;
  final AdTap onTap;
  final bool swipe, mobile;
  final AdsTracker? tracker;
  final String town;

  @override
  State<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends State<AdSlot> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this);
  Timer? _timer;
  bool paused = false;
  Entry? outgoing;
  late Entry shown = widget.rotation.current(widget.slot);
  int changes = 0;
  DateTime? _resumeAt;
  // Counting a genuine view: the ad must be really visible (page in front, app active, at least half of the box on screen).
  Timer? _watch;
  int _visibleMs = 0;
  bool _viewSent = false;

  @override
  void initState() {
    super.initState();
    if (widget.tracker != null) _watch = Timer.periodic(const Duration(milliseconds: 500), (_) => _look());
    // Stagger: the first change of slot k comes after (k+1)/slots of the ad's time, so the boxes change one after another.
    final first = adSeconds(shown, widget.config) * 1000 * (widget.slot + 1) / widget.slots;
    _arm(Duration(milliseconds: first.round()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watch?.cancel();
    if (_viewSent) _finishCurrent();
    controller.dispose();
    super.dispose();
  }

  bool _isVisible() {
    if (!mounted) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final seen = rect.intersect(Offset.zero & MediaQuery.sizeOf(context));
    return !seen.isEmpty && seen.width * seen.height >= .5 * rect.width * rect.height;
  }

  void _look() {
    if (_isVisible()) _visibleMs += 500;
    if (!_viewSent && _visibleMs >= 1000) {
      _viewSent = true;
      widget.tracker?.view(shown.id, town: widget.town);
    }
  }

  /// The ad is leaving the box: report the rest of its time on screen, or that it was due but never really seen.
  void _finishCurrent() {
    final tracker = widget.tracker;
    if (tracker == null) return;
    if (_viewSent) {
      tracker.time(shown.id, (_visibleMs / 1000).round() - 1, town: widget.town);
    } else {
      tracker.miss(shown.id, town: widget.town);
    }
    _visibleMs = 0;
    _viewSent = false;
  }

  void _arm(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, _tick);
  }

  void _tick() {
    if (!mounted) return;
    if (paused || (_resumeAt != null && DateTime.now().isBefore(_resumeAt!))) {
      _arm(const Duration(seconds: 1));
      return;
    }
    _change(back: false);
  }

  void _change({required bool back}) {
    if (!widget.rotation.step(widget.slot, back: back)) {
      _arm(Duration(seconds: adSeconds(shown, widget.config)));
      return;
    }
    _finishCurrent();
    final next = widget.rotation.current(widget.slot);
    if (widget.config.animation == 'none') {
      // "None": the next ad simply replaces this one.
      setState(() {
        outgoing = null;
        shown = next;
        changes++;
      });
      _arm(Duration(seconds: adSeconds(next, widget.config)));
      return;
    }
    setState(() {
      outgoing = shown;
      shown = next;
      changes++;
    });
    controller
      ..duration = widget.config.transition
      ..forward(from: 0).whenComplete(() {
        if (mounted) setState(() => outgoing = null);
      });
    _arm(Duration(seconds: adSeconds(next, widget.config)));
  }

  /// After a swipe the automatic change waits a few seconds before carrying on.
  void _swiped(bool back) {
    _resumeAt = DateTime.now().add(const Duration(seconds: 5));
    _change(back: back);
  }

  @override
  Widget build(BuildContext context) {
    Widget box(Entry ad) => AdBox(ad: ad, config: widget.config, onTap: widget.onTap, mobile: widget.mobile);
    Widget content = outgoing == null
        ? box(shown)
        : AnimatedBuilder(
            animation: controller,
            builder: (context, _) => adTransitionFrame(_typeOfCurrentChange, Curves.easeInOut.transform(controller.value), box(outgoing!), box(shown)),
          );
    if (widget.swipe) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() > 120) _swiped(v > 0);
        },
        child: content,
      );
    }
    if (!widget.config.pauseOnHover) return content;
    return MouseRegion(
      onEnter: (_) => paused = true,
      onExit: (_) => paused = false,
      child: Listener(onPointerDown: (_) => paused = true, onPointerUp: (_) => paused = false, onPointerCancel: (_) => paused = false, child: content),
    );
  }

  String get _typeOfCurrentChange {
    final a = widget.config.animation;
    if (a != 'mix') return a;
    final keys = adAnimations.keys.where((k) => k != 'none').toList();
    return keys[(changes - 1) % keys.length];
  }
}
