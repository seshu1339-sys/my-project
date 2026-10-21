// Manual check (not part of the apps): draws a big picture, runs it through the same code every upload uses and prints
// what came out. Run on a device/emulator:  flutter run -t tool/webp_probe.dart --flavor customer
// or in a browser:  flutter run -d chrome -t tool/webp_probe.dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ecommerce_app/services/image_compress.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const width = 3000, height = 2000;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final random = math.Random(7);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(3000, 2000), [Colors.green, Colors.orange]),
  );
  for (var i = 0; i < 600; i++) {
    canvas.drawCircle(
      Offset(random.nextDouble() * width, random.nextDouble() * height),
      20 + random.nextDouble() * 120,
      Paint()..color = Color(0x66000000 | random.nextInt(0xFFFFFF)),
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  final result = await prepareImageForUpload(png, 'probe.png');
  final decoded = await ui.instantiateImageCodec(result.bytes);
  final frame = (await decoded.getNextFrame()).image;
  final line = 'WEBP_PROBE original=${png.length}B (${width}x$height png) -> converted=${result.converted} '
      'type=${result.type} ext=${result.ext} size=${result.bytes.length}B isWebp=${isWebp(result.bytes)} '
      'decodedAs=${frame.width}x${frame.height}';
  debugPrint(line);
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text(line, textAlign: TextAlign.center)))));
}
