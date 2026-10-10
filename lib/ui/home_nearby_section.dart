import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'details.dart';
import 'home_widgets.dart';
import 'layout_settings.dart';
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
  });
  final Store store;
  final ComponentLayout nearby;
  final bool located;
  final List<Entry> shops;
  final VoidCallback onLocation;

  @override
  Widget build(BuildContext context) => LayoutSection(
    layout: nearby,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeading(
          title: 'Nearby shops'.tr(context),
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
        for (final shop in shops)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            color: AppTokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              side: const BorderSide(color: AppTokens.border),
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTokens.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront_outlined, color: AppTokens.primary),
              ),
              title: Text(
                shop.text('name'),
                style: const TextStyle(fontWeight: FontWeight.w700),
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
      ],
    ),
  );
}
