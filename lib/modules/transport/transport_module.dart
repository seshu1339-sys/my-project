import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import '../../services/usage.dart';
import 'transport_page.dart';

/// The Transport module. Its own folder, route and Firestore collection ("transport", nothing is stored there yet). For now the
/// page only says it is coming soon.
const transportRoute = '/transport';
const transportCollection = 'transport';

void openTransport(BuildContext context, Store store) {
  Usage.track('transport_click', key: 'transport', label: 'Transport');
  _push(context);
}

void _push(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(settings: const RouteSettings(name: transportRoute), builder: (_) => const TransportPage()),
);

const transportModule = HomeModule(
  id: 'transport',
  title: 'Transport',
  icon: Icons.local_shipping_outlined,
  color: Color(0xFF0F766E),
  route: transportRoute,
  collection: transportCollection,
  open: openTransport,
);
