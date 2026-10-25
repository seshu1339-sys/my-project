import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/strings.dart';
import 'layout_settings.dart';
import 'product_search.dart';
import 'page_widgets.dart';
import 'shared.dart';
import 'shop_map.dart';
import 'shop_page.dart';
import 'screen_view.dart';

class ShopsPage extends StatelessWidget {
  const ShopsPage({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => ScreenView('shops', child: _page(context));

  Widget _page(BuildContext context) {
    final shops = store.nearby();
    final titleLayout = layoutFor(
      context,
      store.entries('settings'),
      'shopsPageAppBarTitle',
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titleLayout.entry
              .text('text', 'Around your neighbourhood')
              .tr(context),
          style: overrideTextStyle(titleLayout.entry),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          pageHeadingText(
            context,
            layout: layoutFor(
              context,
              store.entries('settings'),
              'shopsPageHeading',
            ),
            defaultText: 'Good shops, close by.',
            fontSize: 30,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ProductSearchPage(store: store),
              ),
            ),
            icon: const Icon(Icons.travel_explore_outlined),
            label: Text('Search products near me'.tr(context)),
          ),
          const SizedBox(height: 12),
          Text(
            store.latitude == null
                ? 'Showing shops in your pincode. Use GPS on the home page to search by service radius.'.tr(context)
                : 'Showing shops within each shop’s service radius.'.tr(context),
          ),
          const SizedBox(height: 20),
          if (shops.isEmpty)
            Text('No nearby shops found. Set or change your location on the home page.'.tr(context)),
          if (shops.isNotEmpty)
            ShopMap(
              shops: shops,
              latitude: store.latitude,
              longitude: store.longitude,
              onShop: (shop) => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ShopPage(store: store, shop: shop),
                ),
              ),
            ),
          for (final shop in shops)
            Card(
              child: ListTile(
                leading: const Icon(Icons.storefront),
                title: Text(shop.text('name')),
                subtitle: Text(
                  '${shop.text('address')}\n${store.latitude != null ? '{km} km away'.tr(context, {'km': distanceKm(store.latitude!, store.longitude!, shop.number('latitude'), shop.number('longitude')).toStringAsFixed(1)}) : shop.text('pincode')}',
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
}
