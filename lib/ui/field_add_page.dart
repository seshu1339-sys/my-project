import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/stafflinks/stafflinks_module.dart';
import '../modules/transport/transport_module.dart';
import 'big_option_tile.dart';
import 'screen_view.dart';

/// Staff app > Add: Vendor, Services or Transport. Vendors and service providers register themselves in the vendor app; here the
/// staff member links one to themselves by entering their ID within 30 minutes of the registration (lib/modules/stafflinks). Staff
/// never create a vendor or provider and never change their items or prices. Transport is its own module and says it is coming soon.
/// Only approved staff get here (the workspace is built only for them).
class FieldAddPage extends StatelessWidget {
  const FieldAddPage({super.key, required this.store, this.vendorPage, this.servicesPage});
  final Store store;
  // For tests: what Vendor and Services open (the link pages by default).
  final WidgetBuilder? vendorPage, servicesPage;

  void _open(BuildContext context, WidgetBuilder page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: page));

  @override
  Widget build(BuildContext context) => ScreenView('staff_add', child: _page(context));

  Widget _page(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Who registered with your help?', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text('Vendors and service providers register in the vendor app themselves. Link them here with their ID within 30 minutes.'),
              const SizedBox(height: 16),
              BigOptionTile(
                key: const ValueKey('field-add-vendor'),
                title: 'Vendor',
                subtitle: 'Link a shop by its Vendor ID (VEN-...)',
                icon: Icons.storefront_outlined,
                color: const Color(0xff8c4a22),
                onTap: () => _open(context, vendorPage ?? (_) => StaffLinkPage(store: store, provider: false)),
              ),
              const SizedBox(height: 14),
              BigOptionTile(
                key: const ValueKey('field-add-services'),
                title: 'Services',
                subtitle: 'Link a plumber, electrician and more by their Provider ID (SRV-...)',
                icon: Icons.home_repair_service_outlined,
                color: const Color(0xFFD97706),
                onTap: () => _open(context, servicesPage ?? (_) => StaffLinkPage(store: store, provider: true)),
              ),
              const SizedBox(height: 14),
              BigOptionTile(
                key: const ValueKey('field-add-transport'),
                title: 'Transport',
                subtitle: 'Coming soon',
                icon: Icons.local_shipping_outlined,
                color: const Color(0xFF0F766E),
                onTap: () => openTransport(context, store),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
