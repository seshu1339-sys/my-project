import 'package:flutter/material.dart';

import '../data/store.dart';
import '../ui/shop_page.dart';
import 'home_module.dart';
import 'offers/offers_module.dart';
import 'services/services_module.dart';
import 'transport/transport_module.dart';

// The offers module opens a shop through this callback, so it imports no shop screen itself.
void _openOffers(BuildContext context, Store store) => openOffers(
  context,
  store,
  onShop: (context, shop) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShopPage(store: store, shop: shop))),
);

const _offersModule = HomeModule(
  id: 'offers',
  title: 'Shop Offers',
  icon: Icons.local_offer_outlined,
  color: Color(0xFFB45309),
  route: offersRoute,
  collection: offersCollection,
  open: _openOffers,
);

/// The home-page modules, in the order of their boxes under Today's Offers. The only place that knows all of them.
const homeModules = <HomeModule>[transportModule, servicesModule, _offersModule];
