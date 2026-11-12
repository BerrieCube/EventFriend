import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Opent het bestand in een nieuw tabblad van de browser.
Future<String?> openBytes(String name, String mime, Uint8List bytes) async {
  final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mime.isEmpty ? 'application/octet-stream' : mime));
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
  return null;
}
