import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'details.dart';
import 'home_widgets.dart';
import 'layout_settings.dart';
import 'shared.dart';
import 'shop_map.dart';

/// The "Nearby shops" homepage section: heading, a map (once a location is
/// known), and a list of shop cards. Always appended after the admin's
/// reorderable sections — not itself reorderable.
class HomeNearbySection extends StatelessWidget {
  const HomeNearbySection({
    super.key,
    required this.store,
    required this.nearby,
    required this.located,
    required this.shops,
    required this.onLocation,
    required this.shopCardLayout,
    this.wrapSection = _identitySection,
  });
  final Store store;
  final ComponentLayout nearby;
  final bool located;
  final List<Entry> shops;
  final VoidCallback onLocation;
  final ComponentLayout shopCardLayout;
  final Widget Function(String sectionKey, Widget child) wrapSection;
  static Widget _identitySection(String sectionKey, Widget child) => child;

  @override
  Widget build(BuildContext context) => LayoutSection(
    layout: nearby,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeading(
          title: nearby.entry.text('text', 'Nearby shops').tr(context),
          subtitle: (located
                  ? 'Shops serving your selected location'
                  : 'Choose a location or browse available shops')
              .tr(context),
          action: onLocation,
          actionLabel: (located ? 'Change location' : 'Set location').tr(context),
          appearance: nearby.entry,
        ),
        if (shops.isNotEmpty && located)
          ShopMap(
            key: ValueKey(
              '${store.pincode}-${store.latitude}-${shops.map((e) => e.id).join(',')}',
            ),
            shops: shops,
            latitude: store.latitude,
            longitude: store.longitude,
            height: nearby.height(320, floor: 180),
            onShop: (shop) => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ShopPage(store: store, shop: shop),
              ),
            ),
          ),
        if (shops.isEmpty)
          Text(
            'No nearby shops found. You can change your pincode without enabling GPS.'.tr(context),
          ),
        if (shopCardLayout.visible)
          for (final (i, shop) in shops.indexed)
            _maybeWrapFirst(
              i,
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                color: shopCardLayout.entry.text('backgroundColor').isEmpty
                    ? AppTokens.surface
                    : colorFromHex(shopCardLayout.entry.text('backgroundColor'), AppTokens.surface),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    shopCardLayout.entry.number('radius') > 0
                        ? clampedNumber(shopCardLayout.entry, 'radius', AppTokens.radiusMd, 0, 80)
                        : AppTokens.radiusMd,
                  ),
                  side: shopCardLayout.entry.text('borderColor').isEmpty
                      ? const BorderSide(color: AppTokens.border)
                      : BorderSide(color: colorFromHex(shopCardLayout.entry.text('borderColor'), AppTokens.border)),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      shopCardLayout.entry.number('radius') > 0
                          ? clampedNumber(shopCardLayout.entry, 'radius', AppTokens.radiusMd, 0, 80)
                          : AppTokens.radiusMd,
                    ),
                  ),
                  contentPadding: shopCardLayout.entry.number('padding') > 0
                      ? EdgeInsets.all(clampedNumber(shopCardLayout.entry, 'padding', 16, 0, 48))
                      : null,
                  leading: Container(
                    width: shopCardLayout.entry.number('iconSize') > 0
                        ? clampedNumber(shopCardLayout.entry, 'iconSize', 44, 16, 48) + 12
                        : 44,
                    height: shopCardLayout.entry.number('iconSize') > 0
                        ? clampedNumber(shopCardLayout.entry, 'iconSize', 44, 16, 48) + 12
                        : 44,
                    decoration: const BoxDecoration(
                      color: AppTokens.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: shopCardLayout.entry.text('iconUrl').isEmpty
                        ? Icon(
                            Icons.storefront_outlined,
                            color: AppTokens.primary,
                            size: shopCardLayout.entry.number('iconSize') > 0
                                ? clampedNumber(shopCardLayout.entry, 'iconSize', 24, 16, 48)
                                : 24,
                          )
                        : ClipOval(
                            child: Image.network(
                              shopCardLayout.entry.text('iconUrl'),
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stack) => const Icon(Icons.storefront_outlined, color: AppTokens.primary),
                            ),
                          ),
                  ),
                  title: Text(
                    shop.text('name'),
                    style: sectionTextStyle(shopCardLayout.entry, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${shop.text('address')} • ${shop.text('phone')} ${store.latitude == null ? '' : '• ${distanceKm(store.latitude!, store.longitude!, shop.number('latitude'), shop.number('longitude')).toStringAsFixed(1)} km'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ShopPage(store: store, shop: shop),
                    ),
                  ),
                ),
              ),
            ),
      ],
    ),
  );

  // Only the FIRST rendered shop card carries the 'nearbyShopCard' section
  // key -- it's a shared template (one settings doc for the whole list, not
  // per-shop), and every SectionTapRegion sibling needs a unique key, so
  // wrapping every card with the same key would crash. The template's
  // style still applies to every card either way; only the click-to-select
  // affordance is on the first one.
  Widget _maybeWrapFirst(int index, Widget child) => index == 0 ? wrapSection('nearbyShopCard', child) : child;
}
