import 'package:flutter/material.dart';

import '../services/strings.dart';
import 'design_tokens.dart';

/// The "All Categories" button that sits beside the offers ticker, directly
/// under the header (matches the reference design's red button + scrolling
/// strip row). Tapping it scrolls down to the full Categories grid.
class AllCategoriesButton extends StatelessWidget {
  const AllCategoriesButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.primary,
    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'All Categories'.tr(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}
