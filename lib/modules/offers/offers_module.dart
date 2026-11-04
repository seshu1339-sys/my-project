import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../domain/catalog.dart';
import 'offers_page.dart';

export 'vendor_offers_section.dart';

/// The Vendor Offers module: vendors make offers with their own photos and prices, customers see them. Its own folder, route, collections
/// and Storage folder, with nothing to do with plans or payments. The shop page is passed in by the registry (modules.dart), so this module
/// imports no shop screen.
const offersRoute = '/vendor-offers';
const offersCollection = 'vendorOffers';

void openOffers(BuildContext context, Store store, {void Function(BuildContext context, Entry shop)? onShop}) => Navigator.of(context).push(
  MaterialPageRoute<void>(settings: const RouteSettings(name: offersRoute), builder: (_) => OffersPage(store: store, onShop: onShop)),
);
