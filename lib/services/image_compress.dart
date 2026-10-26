import 'dart:typed_data';

import 'image_compress_native.dart'
    if (dart.library.js_interop) 'image_compress_web.dart'
    as platform;

// Every photo any of the apps uploads (admin catalog, vendor, staff, Quick Add) goes through
// [prepareImageForUpload] first: the longest side is cut to [uploadMaxSide] pixels and the picture is
// re-encoded as WebP, so a 3-8 MB phone photo is stored as roughly 50 KB (a detailed photo still over
// [uploadTargetBytes] is encoded once more at [uploadRetryQuality]). If the device cannot do it, the
// original photo is uploaded unchanged (an upload is never blocked), and the server converts it afterwards
// (functions/image-webp.js).

const uploadMaxSide = 800;
const uploadQuality = 72;
const uploadRetryQuality = 60;
const uploadTargetBytes = 60 * 1024;
// What a person may pick. The 5 MB limit that Storage enforces applies to the compressed result.
const maxOriginalBytes = 15 * 1024 * 1024;

typedef ImageCompressor =
    Future<Uint8List?> Function(
      Uint8List bytes, {
      required int maxSide,
      required int quality,
    });

/// The phone's / browser's own encoder. Replaced in tests.
ImageCompressor imageCompressor = platform.compressToWebp;

class PreparedImage {
  const PreparedImage({
    required this.bytes,
    required this.ext,
    required this.type,
    required this.originalBytes,
    required this.converted,
  });
  final Uint8List bytes;
  final String ext, type;
  final int originalBytes;
  // True when [bytes] is the new WebP, false when the original photo is kept.
  final bool converted;
}

/// True when [bytes] starts with a WebP header ("RIFF....WEBP").
bool isWebp(Uint8List bytes) =>
    bytes.length > 12 &&
    String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
    String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';

({String ext, String type}) _typeOf(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' => (ext: 'png', type: 'image/png'),
    'webp' => (ext: 'webp', type: 'image/webp'),
    _ => (ext: ext.isEmpty ? 'jpg' : ext, type: 'image/jpeg'),
  };
}

Future<PreparedImage> prepareImageForUpload(
  Uint8List bytes,
  String fileName, {
  ImageCompressor? compress,
}) async {
  if (bytes.length > maxOriginalBytes) {
    throw StateError('Choose an image smaller than 15 MB.');
  }
  final original = _typeOf(fileName);
  Uint8List? small;
  try {
    small = await (compress ?? imageCompressor)(
      bytes,
      maxSide: uploadMaxSide,
      quality: uploadQuality,
    );
    // Still heavy (a very detailed photo): once more, a little lighter; the smaller one is kept.
    if (small != null && isWebp(small) && small.length > uploadTargetBytes) {
      final lighter = await (compress ?? imageCompressor)(
        bytes,
        maxSide: uploadMaxSide,
        quality: uploadRetryQuality,
      );
      if (lighter != null && isWebp(lighter) && lighter.length < small.length) small = lighter;
    }
  } catch (_) {
    small = null; // keep the original
  }
  // Use the WebP only when it really is a WebP and is not bigger than a photo that was already small.
  final useIt =
      small != null &&
      small.isNotEmpty &&
      isWebp(small) &&
      (small.length < bytes.length || !isWebp(bytes));
  if (useIt) {
    return PreparedImage(
      bytes: small,
      ext: 'webp',
      type: 'image/webp',
      originalBytes: bytes.length,
      converted: true,
    );
  }
  if (bytes.length > 5 * 1024 * 1024) {
    throw StateError('Choose an image smaller than 5 MB.');
  }
  return PreparedImage(
    bytes: bytes,
    ext: original.ext,
    type: original.type,
    originalBytes: bytes.length,
    converted: false,
  );
}
