import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/strings.dart';
import 'layout_settings.dart';
import 'shared.dart';

/// The trust-badge strip at the very bottom of the homepage (quality,
/// delivery, pricing, support, local-shop and payment reassurances) — purely
/// decorative/static, no catalog data involved.
class HomeFooterBadges extends StatelessWidget {
  const HomeFooterBadges({super.key, required this.settings, this.wrapSection = _identitySection});
  final List<Entry> settings;
  final Widget Function(String sectionKey, Widget child) wrapSection;
  static Widget _identitySection(String sectionKey, Widget child) => child;

  static const _badges = [
    (Icons.eco_outlined, 'Fresh & Premium Quality', 'footerBadge1'),
    (Icons.local_shipping_outlined, 'Fast & Safe Delivery', 'footerBadge2'),
    (Icons.currency_rupee, 'Best Prices Always', 'footerBadge3'),
    (Icons.headset_mic_outlined, 'Easy Returns & Support', 'footerBadge4'),
    (Icons.storefront_outlined, 'Local Shops & Trusted Sellers', 'footerBadge5'),
    (Icons.account_balance_wallet_outlined, 'Pay on Delivery', 'footerBadge6'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Wrap(
      alignment: WrapAlignment.spaceEvenly,
      runSpacing: 16,
      spacing: 16,
      children: [
        for (final (icon, label, key) in _badges)
          Builder(
            builder: (context) {
              final layout = layoutFor(context, settings, key);
              if (!layout.visible) return const SizedBox.shrink();
              final entry = layout.entry;
              final iconSize = entry.number('iconSize') > 0 ? clampedNumber(entry, 'iconSize', 24, 16, 48) : 24.0;
              return wrapSection(
                key,
                SizedBox(
                  width: 160,
                  child: Column(
                    children: [
                      entry.text('iconUrl').isEmpty
                          ? Icon(
                              icon,
                              size: iconSize,
                              color: entry.text('textColor').isEmpty
                                  ? Theme.of(context).colorScheme.primary
                                  : colorFromHex(entry.text('textColor'), Theme.of(context).colorScheme.primary),
                            )
                          : Image.network(
                              entry.text('iconUrl'),
                              width: iconSize,
                              height: iconSize,
                              fit: BoxFit.contain,
                              errorBuilder: (_, error, stack) => Icon(icon, size: iconSize, color: Theme.of(context).colorScheme.primary),
                            ),
                      const SizedBox(height: 6),
                      Text(
                        entry.text('text', label).tr(context),
                        textAlign: TextAlign.center,
                        style: sectionTextStyle(entry, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );
}
