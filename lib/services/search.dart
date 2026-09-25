import 'dart:typed_data';

import '../domain/catalog.dart';

abstract interface class VoiceSearchProvider {
  Future<String> transcribe();
}

abstract interface class ImageSearchProvider {
  Future<String> describe(Uint8List bytes);
}

class SmartSearch {
  const SmartSearch({this.voice, this.image});
  final VoiceSearchProvider? voice;
  final ImageSearchProvider? image;

  /// [categories] lets a query also match a product's category/subcategory
  /// name, not just its own name/description/tags — e.g. searching "Local
  /// services" (a top-level category) still finds a product filed under its
  /// "Plumbing" subcategory, and searching "Plumbing" finds it directly.
  List<Entry> text(
    List<Entry> catalog,
    String query, [
    List<Entry> categories = const [],
  ]) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    final categoryText = _categorySearchIndex(categories);
    return catalog
        .where(
          (e) => words.every(
            (w) =>
                '${e.text('name')} ${e.text('description')} ${e.text('tags')} ${categoryText[e.text('categoryId')] ?? ''}'
                    .toLowerCase()
                    .contains(w),
          ),
        )
        .toList();
  }

  /// Maps each category id to its own name plus every ancestor's name (walking
  /// up `parentId`), so a nested subcategory is reachable by its own name or
  /// any parent category's name. Guards against a malformed cyclic parentId
  /// chain so a bad admin edit can never hang the search box.
  Map<String, String> _categorySearchIndex(List<Entry> categories) {
    final byId = {for (final c in categories) c.id: c};
    final resolved = <String, String>{};
    String chain(String id, Set<String> visiting) {
      final cached = resolved[id];
      if (cached != null) return cached;
      final category = byId[id];
      if (category == null || visiting.contains(id)) return '';
      final parentId = category.text('parentId');
      final ancestors = parentId.isEmpty ? '' : chain(parentId, {...visiting, id});
      final value = '${category.text('name')} $ancestors'.trim();
      resolved[id] = value;
      return value;
    }

    return {for (final c in categories) c.id: chain(c.id, {})};
  }
}
