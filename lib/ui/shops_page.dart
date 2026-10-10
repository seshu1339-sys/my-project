import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'product_search.dart';
import 'shop_map.dart';
import 'shop_page.dart';

class ShopsPage extends StatelessWidget {
  const ShopsPage({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) {
    final shops = store.nearby();
    return Scaffold(
      appBar: AppBar(title: const Text('Around your neighbourhood')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Good shops, close by.',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => ProductSearchPage(store: store)),
            ),
            icon: const Icon(Icons.travel_explore_outlined),
            label: const Text('Search products near me'),
          ),
          const SizedBox(height: 12),
          Text(
            store.latitude == null
                ? 'Showing shops in your pincode. Use GPS on the home page to search by service radius.'
                : 'Showing shops within each shop’s service radius.',
          ),
          const SizedBox(height: 20),
          if (shops.isEmpty)
            const Text(
              'No nearby shops found. Set or change your location on the home page.',
            ),
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
                  '${shop.text('address')}\n${store.latitude != null ? '${distanceKm(store.latitude!, store.longitude!, shop.number('latitude'), shop.number('longitude')).toStringAsFixed(1)} km away' : shop.text('pincode')}',
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
