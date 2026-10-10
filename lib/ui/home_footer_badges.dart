import 'package:flutter/material.dart';

import '../services/strings.dart';

/// The trust-badge strip at the very bottom of the homepage (quality,
/// delivery, pricing, support, local-shop and payment reassurances) — purely
/// decorative/static, no catalog data involved.
class HomeFooterBadges extends StatelessWidget {
  const HomeFooterBadges({super.key});

  static const _badges = [
    (Icons.eco_outlined, 'Fresh & Premium Quality'),
    (Icons.local_shipping_outlined, 'Fast & Safe Delivery'),
    (Icons.currency_rupee, 'Best Prices Always'),
    (Icons.headset_mic_outlined, 'Easy Returns & Support'),
    (Icons.storefront_outlined, 'Local Shops & Trusted Sellers'),
    (Icons.account_balance_wallet_outlined, 'Pay on Delivery'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Wrap(
      alignment: WrapAlignment.spaceEvenly,
      runSpacing: 16,
      spacing: 16,
      children: [
        for (final (icon, label) in _badges)
          SizedBox(
            width: 160,
            child: Column(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 6),
                Text(
                  label.tr(context),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
