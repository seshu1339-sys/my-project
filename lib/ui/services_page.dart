import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/search.dart';
import 'details.dart';
import 'shared.dart';

/// Every visible service-kind product/service entry matching [query] (a
/// blank query matches everything). Shared by [ServicesPage] and the
/// homepage's Local Services preview section so both read the exact same
/// data the exact same way — one implementation, not two.
List<Entry> localServiceEntries(
  Store store,
  SmartSearch searchService, [
  String query = '',
]) => searchService
    .text(store.visible('products'), query, store.visible('categories'))
    .where((entry) => entry.text('kind') == 'service')
    .toList();

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key, required this.store});
  final Store store;
  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final services = localServiceEntries(widget.store, const SmartSearch(), search.text);
      return Scaffold(
        appBar: AppBar(title: const Text('Services')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search services',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            if (services.isEmpty) const Text('No matching services available.'),
            for (final service in services)
              Card(
                child: ListTile(
                  leading: SizedBox(
                    width: 64,
                    child: ProductArt(service, height: 64),
                  ),
                  title: Text(service.text('name')),
                  subtitle: Text(
                    '${money(service.price(widget.store.pincode))} • ${service.text('unit')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ProductPage(store: widget.store, entry: service),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
