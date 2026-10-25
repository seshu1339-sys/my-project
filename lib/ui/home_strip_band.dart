import 'package:flutter/material.dart';

import '../data/store.dart';
import 'home_module_boxes.dart';

/// The band under the Today's Offers cards: the row of product cards (Fresh Fruits & Vegetables) and the Transport / Services boxes.
///
/// Wide ([sideBySide]): the product cards that fit take the left, and the two boxes fill ALL the space to their right (equal width, no
/// empty gap), from the bottom of the Today's Offers cards down to where the Popular Products heading ends (the category tabs line),
/// so they are taller than the cards, with larger icon and text. The width left over after whole cards decides how wide the boxes are,
/// so they stretch to fill the space on any screen. More cards than fit are reached by scrolling the row.
///
/// Narrow: the product cards across the full width, and the two boxes below them, full width.
class HomeStripBand extends StatelessWidget {
  const HomeStripBand({super.key, required this.store, required this.strip, this.heading, required this.sideBySide});
  final Store store;

  /// The row of product cards (empty when there are none).
  final Widget strip;

  /// The Popular Products heading, shown under the cards so the boxes reach down to the category tabs (wide layout only).
  final Widget? heading;
  final bool sideBySide;

  /// One card (110) and the space after it (10), as the strip lays them out.
  static const cardPitch = 120.0;

  /// The least width the two boxes may have (they never get narrower than this).
  static const minBoxesWidth = 190.0;

  @override
  Widget build(BuildContext context) {
    if (!sideBySide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [strip, HomeModuleBoxes(store: store)]);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = ((constraints.maxWidth - minBoxesWidth) / cardPitch).floor().clamp(1, 1000);
        final stripWidth = cards * cardPitch;
        // The left column (cards + heading) decides the height; the boxes are positioned to fill the rest of the width and that whole
        // height. (A Stack, not an IntrinsicHeight: the cards contain layout builders, which cannot give intrinsic sizes.)
        return Stack(
          key: const ValueKey('home-strip-band'),
          children: [
            SizedBox(
              width: constraints.maxWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: stripWidth,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [strip, ?heading]),
                  ),
                ],
              ),
            ),
            Positioned(left: stripWidth, right: 0, top: 0, bottom: 0, child: HomeModuleBoxes(store: store, tall: true)),
          ],
        );
      },
    );
  }
}
