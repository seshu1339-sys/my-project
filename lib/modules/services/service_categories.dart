import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/catalog.dart';

/// One of the fixed service-worker types (Plumber, Electrician, ...). They are records of the Firestore `services` collection
/// (kind: 'serviceType'); assets/services/services_list.json is the built-in copy used when the collection has none. Distinct from a
/// vendor's own service *listing* (kind: 'service', also in `services`).
class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.displayName,
    required this.imageFileName,
    required this.displayOrder,
  });
  final String id;
  final String displayName;
  final String imageFileName;
  final int displayOrder;

  /// A service-type record of the services collection.
  factory ServiceCategory.fromEntry(Entry type) => ServiceCategory(
    id: type.text('typeId', type.id.startsWith('type-') ? type.id.substring(5) : type.id),
    displayName: type.text('name', type.id),
    imageFileName: type.text('imageFileName'),
    displayOrder: type.number('order').round(),
  );
}

Future<List<ServiceCategory>>? _cache;

/// Loads and parses assets/services/services_list.json once per app run
/// (cached), in the JSON's own `display_order` -- callers that want a
/// different order (e.g. the Services page's A-Z list) sort this
/// themselves rather than this function assuming one fixed order. Adding a
/// new entry to the JSON is all a future round needs to do; nothing here
/// hardcodes the 30 current ids.
Future<List<ServiceCategory>> loadServiceCategories() => _cache ??= rootBundle
    .loadString('assets/services/services_list.json')
    .then((raw) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final parsed = [
        for (final item in list)
          ServiceCategory(
            id: item['id'] as String,
            displayName: item['display_name'] as String,
            imageFileName: item['image_file_name'] as String,
            displayOrder: item['display_order'] as int,
          ),
      ]..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      return parsed;
    });
