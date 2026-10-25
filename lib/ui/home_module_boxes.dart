import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/modules.dart';
import '../services/strings.dart';

/// The big colour boxes side by side under the Today's Offers cards, one per home module (Transport, Services). Each has the module's
/// icon and name and opens the module's own page. This widget only reads the list in modules/modules.dart.
class HomeModuleBoxes extends StatelessWidget {
  const HomeModuleBoxes({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        for (final (i, module) in homeModules.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: Material(
              key: ValueKey('home-box-${module.id}'),
              color: module.color,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => module.open(context, store),
                child: SizedBox(
                  height: 120,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(module.icon, size: 44, color: Colors.white),
                      const SizedBox(height: 8),
                      Text(
                        module.title.tr(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
