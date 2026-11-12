/// Bestand openen in een andere app (Android) of nieuw tabblad (web).
library;

export 'open_doc_io.dart' if (dart.library.js_interop) 'open_doc_web.dart';
