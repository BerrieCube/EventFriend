/// Zet opgemaakte notitie-inhoud (Quill Delta JSON) om naar platte tekst,
/// met tekens voor opsommingen en checklists. Gebruikt voor zoeken, de
/// vergrendelscherm-melding, de widget en de PDF-export.
library;

import 'dart:convert';

String deltaToPlain(String? deltaJson, {String fallback = ''}) {
  if (deltaJson == null || deltaJson.isEmpty) return fallback;
  List ops;
  try {
    ops = jsonDecode(deltaJson) as List;
  } catch (_) {
    return fallback;
  }
  final out = <String>[];
  final line = StringBuffer();
  var number = 0;

  void endLine(Map? attrs) {
    final list = attrs?['list'];
    var prefix = '';
    if (list == 'bullet') {
      prefix = '• ';
    } else if (list == 'ordered') {
      number++;
      prefix = '$number. ';
    } else if (list == 'checked') {
      prefix = '☑ ';
    } else if (list == 'unchecked') {
      prefix = '☐ ';
    }
    if (list != 'ordered') number = 0;
    final indent = (attrs?['indent'] as num?)?.toInt() ?? 0;
    out.add('${'  ' * indent}$prefix$line');
    line.clear();
  }

  for (final op in ops) {
    if (op is! Map) continue;
    final insert = op['insert'];
    if (insert is! String) continue; // embeds overslaan
    final attrs = op['attributes'] as Map?;
    final parts = insert.split('\n');
    for (var i = 0; i < parts.length; i++) {
      line.write(parts[i]);
      if (i < parts.length - 1) endLine(attrs);
    }
  }
  if (line.isNotEmpty) endLine(null);
  while (out.isNotEmpty && out.last.trim().isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

/// Delta JSON voor platte tekst (voor oude notities zonder opmaak).
String plainToDelta(String text) {
  final t = text.endsWith('\n') ? text : '$text\n';
  return jsonEncode([
    {'insert': t}
  ]);
}
