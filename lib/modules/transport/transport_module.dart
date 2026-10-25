import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import 'admin_transport.dart';
import 'transport_page.dart';

/// The Transport module. Its own folder, route and Firestore collection ("transport", nothing is stored there yet). For now the
/// page only says it is coming soon.
const transportRoute = '/transport';
const transportCollection = 'transport';

void openTransport(BuildContext context, Store store) => Navigator.of(context).push(
  MaterialPageRoute<void>(settings: const RouteSettings(name: transportRoute), builder: (_) => const TransportPage()),
);

Widget _admin(Store store) => AdminTransportSection(store: store);

const transportModule = HomeModule(
  id: 'transport',
  title: 'Transport',
  icon: Icons.local_shipping_outlined,
  color: Color(0xFF0F766E),
  route: transportRoute,
  collection: transportCollection,
  open: openTransport,
  admin: _admin,
  adminHint: 'Bus tracking and seats (coming soon)',
);
