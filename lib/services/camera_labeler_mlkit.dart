import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import '../domain/camera_search.dart';

/// ML Kit's base model (bundled in the app, so it works with no internet): about 400 general English names such as Vegetable,
/// Fruit, Shirt or Jewellery.
Future<List<CameraLabel>> labelPhoto(String path) async {
  final labeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));
  try {
    final labels = await labeler.processImage(InputImage.fromFilePath(path));
    return [for (final l in labels) CameraLabel(l.label, l.confidence)]..sort((a, b) => b.confidence.compareTo(a.confidence));
  } finally {
    await labeler.close();
  }
}
