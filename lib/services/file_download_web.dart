import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> downloadFile(String name, Uint8List bytes, String mimeType) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final link = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name;
  web.document.body?.append(link);
  link.click();
  link.remove();
  web.URL.revokeObjectURL(url);
}
