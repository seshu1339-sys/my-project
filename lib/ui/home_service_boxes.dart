import 'package:flutter/material.dart';

import '../services/strings.dart';

/// Two big colour boxes side by side under the Today's Offers cards: Transport and Services. Each has an icon and its name. Both
/// open the Services page (the page the header's Services shortcut opened before it moved here).
class HomeServiceBoxes extends StatelessWidget {
  const HomeServiceBoxes({super.key, required this.onServices});
  final VoidCallback onServices;

  static const _boxes = [
    ('transport', 'Transport', Icons.local_shipping_outlined, Color(0xFF0F766E)),
    ('services', 'Services', Icons.home_repair_service_outlined, Color(0xFFD97706)),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        for (final (i, box) in _boxes.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: Material(
              key: ValueKey('home-box-${box.$1}'),
              color: box.$4,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onServices,
                child: SizedBox(
                  height: 120,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(box.$3, size: 44, color: Colors.white),
                      const SizedBox(height: 8),
                      Text(
                        box.$2.tr(context),
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
