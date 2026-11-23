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

/// Eén regel uit een Quill Delta: de tekst-ops plus de regel-opmaak
/// (zoals {'list': 'checked'}).
class NoteLine {
  final List<Map<String, dynamic>> ops;
  Map<String, dynamic>? attrs;
  NoteLine(this.ops, this.attrs);

  String? get list => attrs?['list'] as String?;
  bool get isChecked => list == 'checked';
  bool get isUnchecked => list == 'unchecked';
  bool get isCheckItem => isChecked || isUnchecked;

  String get plain => ops.map((o) => o['insert'] is String ? o['insert'] : '').join();

  void setChecked(bool v) =>
      attrs = {...?attrs, 'list': v ? 'checked' : 'unchecked'};
}

/// Splitst Delta-ops in regels. Regel-opmaak (lijst, inspringing) staat in
/// Quill op het '\n'-teken; overige opmaak (vet, schuin) op de tekst.
List<NoteLine> splitLines(List ops) {
  final lines = <NoteLine>[];
  var cur = <Map<String, dynamic>>[];
  for (final raw in ops) {
    if (raw is! Map) continue;
    final insert = raw['insert'];
    final attrs = (raw['attributes'] as Map?)?.cast<String, dynamic>();
    if (insert is! String) {
      cur.add(Map<String, dynamic>.from(raw)); // embed
      continue;
    }
    final parts = insert.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        cur.add({
          'insert': parts[i],
          if (attrs != null && !_isLineAttrs(attrs)) 'attributes': attrs,
        });
      }
      if (i < parts.length - 1) {
        lines.add(NoteLine(cur, _isLineAttrs(attrs) ? attrs : null));
        cur = [];
      }
    }
  }
  if (cur.isNotEmpty) lines.add(NoteLine(cur, null));
  return lines;
}

const _lineKeys = {'list', 'indent', 'header', 'align', 'blockquote', 'code-block'};
bool _isLineAttrs(dynamic a) =>
    a is Map && a.keys.any((k) => _lineKeys.contains(k));

/// Zet regels terug om naar Delta-ops.
List<Map<String, dynamic>> joinLines(List<NoteLine> lines) => [
      for (final l in lines) ...[
        ...l.ops,
        {
          'insert': '\n',
          if (l.attrs != null && l.attrs!.isNotEmpty) 'attributes': l.attrs,
        },
      ],
    ];

/// Regels van een notitie (Delta JSON); lege lijst bij ongeldige inhoud.
List<NoteLine> linesOf(String? deltaJson) {
  if (deltaJson == null || deltaJson.isEmpty) return [];
  try {
    return splitLines(jsonDecode(deltaJson) as List);
  } catch (_) {
    return [];
  }
}

/// Vinkt regel [index] af of aan; afgevinkte regels gaan naar het einde
/// (zoals in Keep), teruggezette regels na het laatste open item.
String setLineChecked(String deltaJson, int index, bool checked) {
  final lines = linesOf(deltaJson);
  if (index < 0 || index >= lines.length) return deltaJson;
  final l = lines.removeAt(index)..setChecked(checked);
  if (checked) {
    lines.add(l);
  } else {
    final lastOpen = lines.lastIndexWhere((x) => !x.isChecked);
    lines.insert(lastOpen + 1, l);
  }
  return jsonEncode(joinLines(lines));
}

/// Verwijdert alle afgevinkte regels.
String removeCheckedLines(String deltaJson) => jsonEncode(
    joinLines(linesOf(deltaJson).where((l) => !l.isChecked).toList()));
