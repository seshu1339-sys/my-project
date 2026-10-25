import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../domain/catalog.dart';
import '../../services/search.dart';
import '../../services/strings.dart';
import '../../ui/details.dart';
import '../../ui/layout_settings.dart';
import 'service_categories.dart';
import '../../ui/shared.dart';

/// Every visible service-kind product/service entry matching [query] (a
/// blank query matches everything). Shared by [ServicesPage] and the
/// homepage's Local Services preview section so both read the exact same
/// data the exact same way — one implementation, not two.
List<Entry> localServiceEntries(
  Store store,
  SmartSearch searchService, [
  String query = '',
]) => searchService
    .text(store.visibleServices(), query, store.visible('categories'))
    .toList();

/// True when [a] and [b] share at least a 4-5 character prefix -- a vendor
/// listing's own wording ("Plumbing visit") and a fixed service type's
/// noun ("Plumber") are different words that neither contains as a
/// substring, so an exact/substring match (SmartSearch's usual rule) would
/// miss it; a shared short prefix is a decent, cheap stand-in for real
/// stemming. Deliberately requires at least 4 characters in common so
/// short unrelated words ("car", "ac") don't cross-match.
bool _sharesWordStem(String a, String b) {
  if (a == b) return true;
  final shorter = a.length <= b.length ? a.length : b.length;
  if (shorter < 4) return false;
  final stemLen = shorter < 6 ? shorter - 1 : 5;
  return a.substring(0, stemLen) == b.substring(0, stemLen);
}

/// Every real vendor-submitted service-kind listing that plausibly belongs
/// to [category] -- there's no categoryId field linking a vendor's own
/// free-text listing to one of the fixed service types, so this matches
/// on shared word stems between the type's own id (snake_case words, each
/// at least 4 letters so a generic short word like "ac"/"tv" never
/// participates alone) and the listing's name/description/tags.
List<Entry> categoryServiceListings(Store store, ServiceCategory category) {
  final roots = category.id.split('_').where((w) => w.length >= 4).toList();
  if (roots.isEmpty) roots.add(category.id);
  return store.visibleServices().where((entry) {
    // A service provider's listing names its type (typeId); other listings are matched by their words.
    if (entry.text('typeId').isNotEmpty) return entry.text('typeId') == category.id;
    final words = '${entry.text('name')} ${entry.text('description')} ${entry.text('tags')}'
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((w) => w.isNotEmpty);
    return words.any((w) => roots.any((r) => _sharesWordStem(w, r)));
  }).toList();
}

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key, required this.store});
  final Store store;
  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final search = TextEditingController();
  late final Future<List<ServiceCategory>> _categories =
      loadServiceCategories();
  // null = browsing the full A-Z service-type list; set = drilled into one
  // type's own real vendor listings ("two-step" browse, not a combined
  // search across both at once).
  ServiceCategory? _selected;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Re-subscribes this whole page to the store's own live Firestore
    // listener, so a service type's listings (and, once added, any new
    // service-type entry in a future services_list.json) appear without
    // needing a manual refresh.
    listenable: widget.store,
    builder: (context, _) {
      final titleLayout = layoutFor(
        context,
        widget.store.entries('settings'),
        'servicesPageAppBarTitle',
      );
      return Scaffold(
        appBar: AppBar(
          title: Text(
            titleLayout.entry.text('text', 'Services').tr(context),
            style: overrideTextStyle(titleLayout.entry),
          ),
        ),
        body: FutureBuilder<List<ServiceCategory>>(
          future: _categories,
          builder: (context, snapshot) {
            // The service types come from the services collection; the built-in file is the fallback when it has none.
            final stored = widget.store.serviceTypes();
            final categories = stored.isNotEmpty
                ? [for (final type in stored) ServiceCategory.fromEntry(type)]
                : snapshot.data;
            if (categories == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final selected = _selected;
            return selected == null
                ? _categoryList(context, categories)
                : _categoryListings(context, selected);
          },
        ),
      );
    },
  );

  Widget _categoryList(BuildContext context, List<ServiceCategory> all) {
    final query = search.text.trim().toLowerCase();
    final sorted = [...all]
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    final filtered = query.isEmpty
        ? sorted
        : sorted
              .where((c) => c.displayName.toLowerCase().contains(query))
              .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: search,
          autofocus: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Search services'.tr(context),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty) Text('No matching services available.'.tr(context)),
        for (final category in filtered)
          Card(
            child: ListTile(
              leading: _categoryThumb(context, category),
              title: Text(category.displayName),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _selected = category),
            ),
          ),
      ],
    );
  }

  Widget _categoryThumb(BuildContext context, ServiceCategory category) {
    const size = 48.0;
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/services/${category.imageFileName}',
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
        errorBuilder: (_, error, stack) =>
            const SizedBox(width: size, height: size),
      ),
    );
  }

  // The real vendor-submitted listings for one service type -- matched by
  // name/description/tags against that type's own id, the only link
  // available between a fixed service-type and a vendor's free-text
  // service listing (there's no categoryId field connecting them). Uses a
  // shared-prefix match rather than an exact word match so a vendor's own
  // wording ("Plumbing visit") still matches the type's own noun
  // ("Plumber") despite neither containing the other as a substring.
  Widget _categoryListings(BuildContext context, ServiceCategory category) {
    final listings = categoryServiceListings(widget.store, category);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'All services'.tr(context),
              onPressed: () => setState(() => _selected = null),
            ),
            Expanded(
              child: Text(
                category.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (listings.isEmpty)
          Text('No matching services available.'.tr(context)),
        for (final service in listings)
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
    );
  }
}
