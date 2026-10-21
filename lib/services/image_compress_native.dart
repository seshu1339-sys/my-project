
import 'package:flutter/services.dart';

// Android: MainActivity.kt / ImageWebp.kt do the work off the UI thread.
const _channel = MethodChannel('in.locamarket/image');

Future<Uint8List?> compressToWebp(
  Uint8List bytes, {
  required int maxSide,
  required int quality,
}) async {
  try {
    return await _channel.invokeMethod<Uint8List>('compressToWebp', {
      'bytes': bytes,
      'maxSide': maxSide,
      'quality': quality,
    });
  } catch (_) {
    // No native encoder here (tests, desktop, iOS): the caller uploads the original.
    return null;
  }
}
