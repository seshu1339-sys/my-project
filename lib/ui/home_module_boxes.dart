import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/modules.dart';
import '../services/strings.dart';

/// The big colour boxes of the home modules (Transport, Services): one box per module, side by side, equal width. Each has the module's
/// icon and name and opens the module's own page. This widget only reads the list in modules/modules.dart.
///
/// [tall] = false: a row of boxes, [rowHeight] high, as wide as the space it is given (used below the product cards on a phone).
/// [tall] = true: the boxes take all the height they are given, with larger icon and text (used in the gap beside the product cards).
class HomeModuleBoxes extends StatelessWidget {
  const HomeModuleBoxes({super.key, required this.store, this.tall = false});
  final Store store;
  final bool tall;

  static const rowHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, module) in homeModules.indexed) ...[
          if (i > 0) SizedBox(width: tall ? 8 : 12),
          Expanded(
            child: Material(
              key: ValueKey('home-box-${module.id}'),
              color: module.color,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => module.open(context, store),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(module.icon, size: tall ? 52 : 44, color: Colors.white),
                      SizedBox(height: tall ? 14 : 8),
                      // The name shrinks to fit a narrow box instead of being cut.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            module.title.tr(context),
                            maxLines: 1,
                            style: TextStyle(color: Colors.white, fontSize: tall ? 24 : 20, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    return tall
        ? row
        : Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(height: rowHeight, child: row),
          );
  }
}
