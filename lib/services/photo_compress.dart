import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The largest vendor item photo uploaded (owner, 16 Nov 2026: under 100 KB, made on the phone before the upload).
const itemPhotoMaxBytes = 100 * 1024;

/// A JPEG of [bytes] under [maxBytes]: at most 800 px on its long side, the quality lowered (and then the size) until it fits.
/// Null when the file is not a photo.
Uint8List? shrinkPhoto(Uint8List bytes, {int maxBytes = itemPhotoMaxBytes}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  var photo = img.bakeOrientation(decoded);
  for (final side in const [800, 640, 480, 360]) {
    if (photo.width > side || photo.height > side) {
      photo = photo.width >= photo.height ? img.copyResize(photo, width: side) : img.copyResize(photo, height: side);
    }
    for (final quality in const [80, 70, 60, 50, 40]) {
      final jpg = img.encodeJpg(photo, quality: quality);
      if (jpg.length <= maxBytes) return jpg;
    }
  }
  return img.encodeJpg(photo, quality: 35);
}

/// [shrinkPhoto] away from the screen's thread (on a phone).
Future<Uint8List?> shrinkPhotoInBackground(Uint8List bytes) => kIsWeb ? Future.value(shrinkPhoto(bytes)) : compute(shrinkPhoto, bytes);
