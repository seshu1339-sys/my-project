import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import 'services_page.dart';

/// The Services module: the A-Z list of service types and the real service listings under each. Its own route and folder.
///
/// Data: its own Firestore collection "services": the service LISTINGS (kind "service": the vendors' and the admin's services) and the
/// fixed service TYPES (kind "serviceType": Plumber, Electrician, ...). Services are never stored in, or listed with, products.
/// (assets/services/services_list.json is the built-in copy of the types, used only while the collection has none.)
const servicesRoute = '/services';
const servicesCollection = 'services';

void openServices(BuildContext context, Store store) => Navigator.of(context).push(
  MaterialPageRoute<void>(settings: const RouteSettings(name: servicesRoute), builder: (_) => ServicesPage(store: store)),
);

const servicesModule = HomeModule(
  id: 'services',
  title: 'Services',
  icon: Icons.home_repair_service_outlined,
  color: Color(0xFFD97706),
  route: servicesRoute,
  collection: servicesCollection,
  open: openServices,
);
