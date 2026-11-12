import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Schrijft het bestand naar een tijdelijke map en opent het met de
/// app die Android daarvoor kiest (PDF-viewer, Word, enz.).
Future<String?> openBytes(String name, String mime, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[^\w\-. ]'), '_');
  final f = File('${dir.path}/$safe');
  await f.writeAsBytes(bytes, flush: true);
  final r = await OpenFilex.open(f.path, type: mime.isEmpty ? null : mime);
  return r.type == ResultType.done ? null : r.message;
}
