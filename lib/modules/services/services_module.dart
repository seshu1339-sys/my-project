import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import 'services_page.dart';

/// The Services module: the A-Z list of service types and the real service listings under each. Its own route and folder.
///
/// Data: the service TYPES are the module's own file (assets/services/services_list.json). The service LISTINGS are still the records
/// of kind "service" in the shared products collection, because vendors and Quick Add create them there; moving them into a
/// collection of their own is a data migration and is not done yet (so [HomeModule.collection] is left empty).
const servicesRoute = '/services';

void openServices(BuildContext context, Store store) => Navigator.of(context).push(
  MaterialPageRoute<void>(settings: const RouteSettings(name: servicesRoute), builder: (_) => ServicesPage(store: store)),
);

const servicesModule = HomeModule(
  id: 'services',
  title: 'Services',
  icon: Icons.home_repair_service_outlined,
  color: Color(0xFFD97706),
  route: servicesRoute,
  open: openServices,
);
