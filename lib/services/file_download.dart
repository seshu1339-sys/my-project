import 'dart:typed_data';

import 'file_download_stub.dart' if (dart.library.js_interop) 'file_download_web.dart' as platform;

/// Saves [bytes] as a file the person can open: a download in the browser (the admin panel is a website). Elsewhere there is nothing
/// to save to, so it reports that instead.
Future<void> downloadFile(String name, Uint8List bytes, String mimeType) => platform.downloadFile(name, bytes, mimeType);
