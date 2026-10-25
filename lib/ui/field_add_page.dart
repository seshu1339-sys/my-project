import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../modules/transport/transport_module.dart';
import 'big_option_tile.dart';
import 'screen_view.dart';
import '../services/usage.dart';

/// Staff app > Add: what the staff member is adding, the same three options as the vendor app's home. A vendor opens [vendorForm];
/// Services first asks which service (the admin's service types), then opens [serviceForm] for it; Transport is its own module
/// (lib/modules/transport) and says it is coming soon. Only approved staff get here (the workspace is built only for them).
class FieldAddPage extends StatelessWidget {
  const FieldAddPage({super.key, required this.store, required this.vendorForm, required this.serviceForm});
  final Store store;
  final WidgetBuilder vendorForm;
  final Widget Function(BuildContext context, Entry serviceType) serviceForm;

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
              Text('What are you adding?', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              BigOptionTile(
                key: const ValueKey('field-add-vendor'),
                title: 'Vendor',
                subtitle: 'A shop and the items it sells',
                icon: Icons.storefront_outlined,
                color: const Color(0xff8c4a22),
                onTap: () => _open(context, vendorForm),
              ),
              const SizedBox(height: 14),
              BigOptionTile(
                key: const ValueKey('field-add-services'),
                title: 'Services',
                subtitle: 'A plumber, electrician, tutor and more',
                icon: Icons.home_repair_service_outlined,
                color: const Color(0xFFD97706),
                onTap: () => _open(context, (_) => FieldServiceTypePage(store: store, serviceForm: serviceForm)),
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

/// The service types from the admin's list (Plumber, Electrician, ...), to choose which service the provider being added offers.
class FieldServiceTypePage extends StatefulWidget {
  const FieldServiceTypePage({super.key, required this.store, required this.serviceForm});
  final Store store;
  final Widget Function(BuildContext context, Entry serviceType) serviceForm;
  @override
  State<FieldServiceTypePage> createState() => _FieldServiceTypePageState();
}

class _FieldServiceTypePageState extends State<FieldServiceTypePage> {
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    Usage.screen('staff_service_types');
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Widget _thumb(Entry type) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.asset(
      'assets/services/${type.text('imageFileName')}',
      width: 48,
      height: 48,
      fit: BoxFit.cover,
      errorBuilder: (_, error, stack) => const SizedBox(width: 48, height: 48, child: Icon(Icons.home_repair_service_outlined)),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Which service?')),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final q = search.text.trim().toLowerCase();
        final types = [
          for (final t in widget.store.serviceTypes())
            if (q.isEmpty || t.text('name').toLowerCase().contains(q)) t,
        ]..sort((a, b) {
            final byOrder = a.number('order', 999).compareTo(b.number('order', 999));
            return byOrder != 0 ? byOrder : a.text('name').compareTo(b.text('name'));
          });
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const ValueKey('field-service-search'),
              controller: search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search services', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (types.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(q.isEmpty ? 'The admin has not added any service types yet.' : 'No service matches "${search.text.trim()}".'),
              ),
            for (final type in types)
              Card(
                child: ListTile(
                  key: ValueKey('field-service-type-${type.id}'),
                  leading: _thumb(type),
                  title: Text(type.text('name', type.id)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => widget.serviceForm(context, type))),
                ),
              ),
          ],
        );
      },
    ),
  );
}
