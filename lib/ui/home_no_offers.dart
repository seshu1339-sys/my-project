import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/strings.dart';
import 'design_tokens.dart';

/// Shown in Today's Offers' place when the customer's town has no offers and
/// there are no general ones to fall back on, so the page never shows an
/// empty box. The admin can reword it (Business settings -> noOffersMessage;
/// `{town}` is replaced by the town's name).
class NoOffersNotice extends StatelessWidget {
  const NoOffersNotice({super.key, required this.store, this.onLocation});
  final Store store;
  // Tapping the notice opens the location dialog (used when no location is chosen yet).
  final VoidCallback? onLocation;

  @override
  Widget build(BuildContext context) {
    final custom = store.business.text('noOffersMessage');
    final text = !store.hasPlace
        ? 'Choose your location to see offers for your town.'.tr(context)
        : custom.isNotEmpty
        ? custom.replaceAll('{town}', store.town)
        : 'No offers in {town} yet. Check back soon!'.tr(context, {
            'town': store.town,
          });
    final box = Container(
      key: const ValueKey('no-offers-notice'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTokens.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.local_offer_outlined, color: AppTokens.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return store.hasPlace || onLocation == null
        ? box
        : InkWell(onTap: onLocation, child: box);
  }
}
