import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/strings.dart';
import 'home_product_grid.dart';
import 'home_product_tile.dart';
import 'home_section_heading.dart';
import 'layout_settings.dart';
import 'home_section_config.dart';

/// The "Local Services" homepage section — a preview grid over the exact
/// same service-kind entries `ServicesPage` lists (see
/// `localServiceEntries` in modules/services/services_page.dart), reusing the same product
/// card widgets as Popular Products. "View all" opens the full ServicesPage.
class HomeLocalServicesSection extends StatelessWidget {
  const HomeLocalServicesSection({
    super.key,
    required this.store,
    required this.settings,
    required this.localServices,
    required this.shopNameById,
    required this.onServices,
    required this.onProduct,
  });
  final Store store;
  final List<Entry> settings;
  final List<Entry> localServices;
  final Map<String, String> shopNameById;
  final VoidCallback onServices;
  final ValueChanged<Entry> onProduct;

  @override
  Widget build(BuildContext context) {
    final layout = layoutFor(context, settings, 'localServices');
    return LayoutSection(
      layout: layout,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeSectionHeading(
            title: layout.entry.text('text', 'Local Services').tr(context),
            subtitle: 'Book trusted help near you'.tr(context),
            action: onServices,
            appearance: sectionConfig(settings, 'localServices'),
          ),
          if (localServices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Services will appear here when available.'.tr(context),
              ),
            ),
          HomeProductGrid(
            entries: localServices.take(6).toList(),
            appearance: layout.entry,
            itemBuilder: (entry) => HomeProductTile(
              entry: entry,
              price: entry.price(store.pincode),
              appearance: layout.styled(context, fontSize: 16),
              shopName: shopNameById[entry.text('shopId')] ?? '',
              onOpen: () => onProduct(entry),
              onAdd: null,
            ),
          ),
        ],
      ),
    );
  }
}
