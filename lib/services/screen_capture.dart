import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// The automatic screenshot of a problem (AI Agent + Health System part 2, 17 Nov 2026): a picture of the app's own screen at the
/// moment a problem happens, attached to its record for the admin.
///
/// Privacy: EVERY text field on the screen is covered with a grey box before the picture leaves the device, so a password, an OTP,
/// a card or UPI number, or anything else typed never shows. Areas wrapped in [SensitiveArea] are covered as well. Only the app's own
/// screen is captured (never the phone's other apps or the system bars). Payment pages of the payment company open outside the app
/// and are never in it.
///
/// Size: about 480 pixels wide, JPEG, at most ~110 KB (Firestore, free); deleted when the problem is solved or after 30 days.
class ScreenCapture {
  ScreenCapture._();

  /// The app's root RepaintBoundary (lib/ui/support_shell.dart puts it around every app).
  static final boundaryKey = GlobalKey(debugLabel: 'screen-capture');

  static const targetWidth = 480.0;
  static const maxBytes = 110 * 1024;

  /// Test seam: a fixed picture instead of the real screen (also read by app_monitoring to take pictures in tests).
  static Future<String?> Function()? testCapture;

  /// A base64 JPEG of the screen with the text fields covered, or null when it cannot be made (never throws).
  static Future<String?> capture() async {
    if (testCapture != null) return testCapture!();
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || !boundary.attached || boundary.size.isEmpty) return null;
      final ratio = (targetWidth / boundary.size.width).clamp(0.25, 1.0);
      final masks = [for (final r in sensitiveRects(boundary)) Rect.fromLTRB(r.left * ratio, r.top * ratio, r.right * ratio, r.bottom * ratio)];
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width, h = image.height;
      image.dispose();
      if (data == null) return null;
      final jpeg = await compute(_encode, (data.buffer.asUint8List(), w, h, [for (final m in masks) [m.left, m.top, m.right, m.bottom]]));
      return jpeg == null ? null : base64Encode(jpeg);
    } catch (_) {
      return null;
    }
  }

  /// The rectangles to cover, in the boundary's own coordinates: every editable text and every [SensitiveArea].
  static List<Rect> sensitiveRects(RenderObject root) {
    final out = <Rect>[];
    void visit(RenderObject o) {
      if (o is RenderEditable || o is _RenderSensitive) {
        if (o is RenderBox && o.hasSize && o.attached) {
          try {
            final rect = MatrixUtils.transformRect(o.getTransformTo(root), Offset.zero & o.size).inflate(4);
            out.add(rect);
          } catch (_) {/* not laid out under the boundary */}
        }
        if (o is _RenderSensitive) return;
      }
      o.visitChildren(visit);
    }

    root.visitChildren(visit);
    return out;
  }
}

/// Encodes the picture as JPEG with the [masks] filled grey (runs off the UI thread on Android).
Uint8List? _encode((Uint8List, int, int, List<List<double>>) a) {
  final (rgba, w, h, masks) = a;
  try {
    final picture = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
    final grey = img.ColorRgb8(170, 170, 170);
    for (final m in masks) {
      img.fillRect(picture, x1: m[0].floor().clamp(0, w - 1), y1: m[1].floor().clamp(0, h - 1), x2: m[2].ceil().clamp(0, w - 1), y2: m[3].ceil().clamp(0, h - 1), color: grey);
    }
    final flat = picture.numChannels == 4 ? img.Image.from(picture).convert(numChannels: 3) : picture;
    for (final q in const [55, 40, 28]) {
      final out = img.encodeJpg(flat, quality: q);
      if (out.length <= ScreenCapture.maxBytes) return out;
    }
    final half = img.copyResize(flat, width: (w / 2).round());
    final out = img.encodeJpg(half, quality: 35);
    return out.length <= ScreenCapture.maxBytes ? out : null;
  } catch (_) {
    return null;
  }
}

/// Anything inside is covered in the automatic screenshot, even if it is not a text field (for example a shown UPI ID or a card).
class SensitiveArea extends SingleChildRenderObjectWidget {
  const SensitiveArea({super.key, super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSensitive();
}

class _RenderSensitive extends RenderProxyBox {}
