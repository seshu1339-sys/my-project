import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// Web: the browser decodes the photo (applying its rotation), draws it smaller on a canvas and encodes WebP.
// Browsers that cannot encode WebP (older Safari) return something else; that is reported as "no result" and
// the original is uploaded, then converted by the server.
Future<Uint8List?> compressToWebp(
  Uint8List bytes, {
  required int maxSide,
  required int quality,
}) async {
  try {
    final blob = web.Blob([bytes.toJS].toJS);
    final bitmap = await web.window.createImageBitmap(blob).toDart;
    final scale = math.min(1.0, maxSide / math.max(bitmap.width, bitmap.height));
    final width = math.max(1, (bitmap.width * scale).round());
    final height = math.max(1, (bitmap.height * scale).round());
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = width
      ..height = height;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.drawImage(bitmap, 0, 0, width.toDouble(), height.toDouble());
    bitmap.close();
    final done = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? result) => done.complete(result)).toJS,
      'image/webp',
      (quality / 100).toJS,
    );
    final out = await done.future;
    if (out == null || out.type != 'image/webp') return null;
    final buffer = await out.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } catch (_) {
    return null;
  }
}
