import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/item_shops.dart';
import 'entry_editor.dart';

/// The shops with no place on the map (latitude and longitude), for whom customers see no distance and no road. Empty when every
/// shop has one.
List<Entry> shopsWithoutLocation(Store store) =>
    [for (final s in store.entries('shops')) if (!shopOnMap(s)) s]..sort((a, b) => a.text('name').toLowerCase().compareTo(b.text('name').toLowerCase()));

/// Settings > Shops without location: every shop missing its latitude and longitude, each with Fix, which opens the shop's own form.
class AdminShopsLocationPage extends StatelessWidget {
  const AdminShopsLocationPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final missing = shopsWithoutLocation(store);
      return ListView(
        key: const ValueKey('admin-shops-location'),
        padding: const EdgeInsets.all(16),
        children: [
          Text('Shops without location', style: Theme.of(context).textTheme.headlineSmall),
          const Text(
            'Customers see how far a shop is, and the road to it, only when the shop has its latitude and longitude. To fix one: '
            'open it, type its latitude and longitude (in Google Maps, press and hold on the shop and copy the two numbers), and Save.',
          ),
          const SizedBox(height: 12),
          if (missing.isEmpty)
            const ListTile(
              key: ValueKey('shops-location-all-good'),
              leading: Icon(Icons.check_circle, color: Colors.green),
              title: Text('Every shop has its place on the map.'),
            )
          else
            Text('${missing.length} shop${missing.length == 1 ? '' : 's'} without location', key: const ValueKey('shops-location-count'), style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final shop in missing)
            Card(
              key: ValueKey('shop-no-location-${shop.id}'),
              child: ListTile(
                leading: const Icon(Icons.location_off_outlined),
                title: Text(shop.text('name', shop.id)),
                subtitle: Text([shop.text('town'), shop.text('address'), shop.text('phone')].where((x) => x.isNotEmpty).join(' • ')),
                trailing: FilledButton.tonal(
                  key: ValueKey('fix-shop-${shop.id}'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EntryEditor(store: store, collection: 'shops', entry: shop))),
                  child: const Text('Fix'),
                ),
              ),
            ),
        ],
      );
    },
  );
}
