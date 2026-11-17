/// Gedeelde opmaak voor alle PDF's: een ingebouwd lettertype (zodat tekens
/// als – en • goed verschijnen) en tekst met klikbare links.
library;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

pw.ThemeData? _theme;

Future<pw.ThemeData> pdfTheme() async {
  if (_theme != null) return _theme!;
  Future<pw.Font> load(String n) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-$n.ttf'));
  return _theme = pw.ThemeData.withFont(
    base: await load('Regular'),
    bold: await load('Bold'),
    italic: await load('Italic'),
    boldItalic: await load('BoldItalic'),
  );
}

final _url = RegExp(r'''((https?://|www\.)[^\s<>"']+[^\s<>"'.,;:!?)\]])''',
    caseSensitive: false);

/// Splitst tekst in stukken; links krijgen een klikbare annotatie.
List<(String, String?)> splitLinks(String text) {
  final out = <(String, String?)>[];
  var i = 0;
  for (final m in _url.allMatches(text)) {
    if (m.start > i) out.add((text.substring(i, m.start), null));
    final t = m.group(0)!;
    out.add((t, t.toLowerCase().startsWith('www.') ? 'https://$t' : t));
    i = m.end;
  }
  if (i < text.length) out.add((text.substring(i), null));
  return out;
}

/// Tekst waarin webadressen klikbaar zijn.
pw.Widget linkedText(String text, {pw.TextStyle? style}) {
  final parts = splitLinks(text);
  if (parts.every((p) => p.$2 == null)) return pw.Text(text, style: style);
  return pw.RichText(
    text: pw.TextSpan(style: style, children: [
      for (final p in parts)
        p.$2 == null
            ? pw.TextSpan(text: p.$1)
            : pw.TextSpan(
                text: p.$1,
                style: const pw.TextStyle(
                    color: PdfColors.blue700,
                    decoration: pw.TextDecoration.underline),
                annotation: pw.AnnotationUrl(p.$2!),
              ),
    ]),
  );
}
