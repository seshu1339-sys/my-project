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
  List<Entry> text(List<Entry> catalog, String query) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    return catalog
        .where(
          (e) => words.every(
            (w) =>
                '${e.text('name')} ${e.text('description')} ${e.text('tags')}'
                    .toLowerCase()
                    .contains(w),
          ),
        )
        .toList();
  }
}
