import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../domain/right_boxes.dart';
import '../services/ad_tracker.dart';
import 'ad_visibility.dart';
import 'shared.dart';

/// The Right Side Ad Boxes: every box exactly the same size ([rightBoxHeight] high, the width of the column it is in), one under
/// the other. Customers see only the photo -- no number, no label. A box without a photo shows the "your ad here" placeholder.
/// A box with a vendor's shop ad (a photo and an ad id) reports to [tracker] when it has really been seen for a second, and when it is
/// tapped, so the vendor's total views add up (functions/ad-tracking.js).
class RightAdBoxes extends StatelessWidget {
  const RightAdBoxes({super.key, required this.settings, required this.onTarget, this.tracker, this.town = ''});
  final List<Entry> settings;
  final ValueChanged<String> onTarget;
  // Counts the views of the shop ads (null = not counted: the admin's previews, the demo); [town] is the customer's town for the reports.
  final AdsTracker? tracker;
  final String town;

  @override
  Widget build(BuildContext context) {
    final boxes = shownRightBoxes(rightBoxesRecord(settings));
    if (boxes.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('right-ad-boxes'),
      children: [
        for (final box in boxes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              key: ValueKey('right-box-${box.number}'),
              height: rightBoxHeight,
              width: double.infinity,
              child: _SeenCounter(
                adId: box.countsViews ? box.adId : '',
                tracker: tracker,
                town: town,
                child: Material(
                  color: box.imageUrl.isEmpty ? const Color(0xFFE5E7EB) : box.color.isEmpty ? Colors.white : colorFromHex(box.color, Colors.white),
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: box.hasTarget
                        ? () {
                            if (box.countsViews) tracker?.tap(box.adId, town: town);
                            onTarget(box.target);
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
              ),
            ),
          ),
      ],
    );
  }
}

/// Reports one view of [adId] once the box has been on screen for a second (the tracker and the server drop repeats within 30 minutes).
/// Does nothing for a box without a shop ad or without a tracker.
class _SeenCounter extends StatefulWidget {
  const _SeenCounter({required this.adId, required this.tracker, required this.town, required this.child});
  final String adId, town;
  final AdsTracker? tracker;
  final Widget child;
  @override
  State<_SeenCounter> createState() => _SeenCounterState();
}

class _SeenCounterState extends State<_SeenCounter> {
  Timer? _watch;
  int _visibleMs = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_SeenCounter old) {
    super.didUpdateWidget(old);
    // Another ad in the box (the admin linked another vendor): its own view.
    if (old.adId != widget.adId || old.tracker != widget.tracker) _start();
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
