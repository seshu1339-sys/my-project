import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../domain/right_boxes.dart';
import 'shared.dart';

/// The Right Side Ad Boxes: every box exactly the same size ([rightBoxHeight] high, the width of the column it is in), one under
/// the other. Customers see only the photo -- no number, no label. Boxes without a photo are not built at all.
class RightAdBoxes extends StatelessWidget {
  const RightAdBoxes({super.key, required this.settings, required this.onTarget});
  final List<Entry> settings;
  final ValueChanged<String> onTarget;

  @override
  Widget build(BuildContext context) {
    final boxes = liveRightBoxes(rightBoxesRecord(settings));
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
              child: Material(
                color: box.color.isEmpty ? Colors.white : colorFromHex(box.color, Colors.white),
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: box.hasTarget ? () => onTarget(box.target) : null,
                  child: Image.network(
                    box.imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: rightBoxHeight,
                    errorBuilder: (_, error, stack) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
