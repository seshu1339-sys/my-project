import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/services/image_compress.dart';

Uint8List _webp(int length) {
  final bytes = Uint8List(length);
  bytes.setAll(0, 'RIFF'.codeUnits);
  bytes.setAll(8, 'WEBP'.codeUnits);
  return bytes;
}

Uint8List _jpeg(int length) => Uint8List(length)..setAll(0, [0xFF, 0xD8, 0xFF]);

void main() {
  test('a big JPEG photo is uploaded as the smaller WebP', () async {
    final photo = _jpeg(4 * 1024 * 1024);
    final prepared = await prepareImageForUpload(
      photo,
      'IMG_2026.JPG',
      compress: (bytes, {required maxSide, required quality}) async {
        expect(maxSide, 1600);
        expect(quality, 80);
        return _webp(180 * 1024);
      },
    );
    expect(prepared.converted, isTrue);
    expect(prepared.ext, 'webp');
    expect(prepared.type, 'image/webp');
    expect(isWebp(prepared.bytes), isTrue);
    expect(prepared.bytes.length, 180 * 1024);
    expect(prepared.originalBytes, 4 * 1024 * 1024);
  });

  test('a PNG is converted too', () async {
    final prepared = await prepareImageForUpload(
      Uint8List(2 * 1024 * 1024),
      'logo.png',
      compress: (bytes, {required maxSide, required quality}) async => _webp(50 * 1024),
    );
    expect(prepared.type, 'image/webp');
    expect(prepared.ext, 'webp');
  });

  test('when the device cannot convert, the original is uploaded unchanged and nothing is blocked', () async {
    for (final failing in <ImageCompressor>[
      (bytes, {required maxSide, required quality}) async => null,
      (bytes, {required maxSide, required quality}) async => throw StateError('no encoder'),
      (bytes, {required maxSide, required quality}) async => Uint8List(0),
      // a browser that cannot encode WebP hands back a PNG/JPEG instead
      (bytes, {required maxSide, required quality}) async => _jpeg(1000),
    ]) {
      final photo = _jpeg(1024 * 1024);
      final prepared = await prepareImageForUpload(photo, 'a.jpg', compress: failing);
      expect(prepared.converted, isFalse);
      expect(prepared.bytes, same(photo));
      expect(prepared.ext, 'jpg');
      expect(prepared.type, 'image/jpeg');
    }
    final png = await prepareImageForUpload(Uint8List(100), 'a.PNG', compress: (b, {required maxSide, required quality}) async => null);
    expect(png.type, 'image/png');
    expect(png.ext, 'png');
  });

  test('a photo that is already a small WebP is not replaced by a bigger one', () async {
    final small = _webp(40 * 1024);
    final prepared = await prepareImageForUpload(
      small,
      'x.webp',
      compress: (bytes, {required maxSide, required quality}) async => _webp(60 * 1024),
    );
    expect(prepared.converted, isFalse);
    expect(prepared.bytes, same(small));
    expect(prepared.type, 'image/webp');
    // ...but a smaller result is used
    final shrunk = await prepareImageForUpload(
      small,
      'x.webp',
      compress: (bytes, {required maxSide, required quality}) async => _webp(20 * 1024),
    );
    expect(shrunk.converted, isTrue);
    expect(shrunk.bytes.length, 20 * 1024);
  });

  test('photos up to 15 MB can be picked because they are shrunk; unshrinkable ones over 5 MB are refused', () async {
    final huge = _jpeg(16 * 1024 * 1024);
    await expectLater(
      prepareImageForUpload(huge, 'a.jpg', compress: (b, {required maxSide, required quality}) async => _webp(100)),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('15 MB'))),
    );
    final big = _jpeg(8 * 1024 * 1024);
    final converted = await prepareImageForUpload(big, 'a.jpg', compress: (b, {required maxSide, required quality}) async => _webp(300 * 1024));
    expect(converted.bytes.length, 300 * 1024);
    // no encoder available and still over what Storage accepts
    await expectLater(
      prepareImageForUpload(big, 'a.jpg', compress: (b, {required maxSide, required quality}) async => null),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('5 MB'))),
    );
  });

  test('without any platform encoder (as in tests) the default path falls back to the original', () async {
    final photo = _jpeg(2048);
    final prepared = await prepareImageForUpload(photo, 'a.jpg');
    expect(prepared.converted, isFalse);
    expect(prepared.bytes, same(photo));
  });

  test('isWebp only accepts real WebP headers', () {
    expect(isWebp(_webp(100)), isTrue);
    expect(isWebp(_jpeg(100)), isFalse);
    expect(isWebp(Uint8List(5)), isFalse);
  });
}
