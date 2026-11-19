/// Import van Google Keep-notities uit een Google Takeout-export
/// (.zip met per notitie een .json-bestand, plus de bijlagen).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'note_text.dart';
import 'store.dart';

class KeepNote {
  final String id;
  final String title;
  final String content; // Quill Delta JSON
  final bool pinned;
  final bool archived;
  final List<String> labels;
  final DateTime created;
  final DateTime updated;
  final List<Uint8List> images;

  KeepNote(
      {required this.id,
      required this.title,
      required this.content,
      required this.pinned,
      required this.archived,
      required this.labels,
      required this.created,
      required this.updated,
      required this.images});
}

class KeepImportResult {
  final List<KeepNote> notes;
  final int skippedTrashed;
  KeepImportResult(this.notes, this.skippedTrashed);
}

String _base(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

DateTime _usec(dynamic v, DateTime fallback) =>
    v is num && v > 0 ? DateTime.fromMicrosecondsSinceEpoch(v.toInt()) : fallback;

/// Leest een Takeout-zip of losse Keep-.json-bestanden.
KeepImportResult parseKeep(List<(String, Uint8List)> files) {
  final all = <(String, Uint8List)>[];
  for (final f in files) {
    if (f.$1.toLowerCase().endsWith('.zip')) {
      for (final e in ZipDecoder().decodeBytes(f.$2)) {
        if (e.isFile) all.add((e.name, e.content));
      }
    } else {
      all.add(f);
    }
  }
  // Bijlagen opzoeken op naam zonder extensie (Takeout wisselt .jpg/.jpeg).
  final media = <String, Uint8List>{};
  for (final f in all) {
    final n = f.$1.toLowerCase();
    if (n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp')) {
      media[_base(f.$1)] = f.$2;
    }
  }

  final notes = <KeepNote>[];
  var trashed = 0;
  for (final f in all) {
    if (!f.$1.toLowerCase().endsWith('.json')) continue;
    Map<String, dynamic> m;
    try {
      final d = jsonDecode(utf8.decode(f.$2, allowMalformed: true));
      if (d is! Map<String, dynamic>) continue;
      m = d;
    } catch (_) {
      continue;
    }
    // Alleen echte Keep-notities (andere Takeout-json's overslaan).
    if (!m.containsKey('textContent') && !m.containsKey('listContent')) continue;
    if (m['isTrashed'] == true) {
      trashed++;
      continue;
    }
    final now = DateTime.now();
    final created = _usec(m['createdTimestampUsec'], now);
    final updated = _usec(m['userEditedTimestampUsec'], created);
    final ops = <Map<String, dynamic>>[];
    final text = (m['textContent'] as String? ?? '').replaceAll('\r\n', '\n');
    if (text.trim().isNotEmpty) {
      ops.add({'insert': text.endsWith('\n') ? text : '$text\n'});
    }
    for (final item in (m['listContent'] as List? ?? const [])) {
      if (item is! Map) continue;
      final t = (item['text'] as String? ?? '').replaceAll('\n', ' ');
      if (t.isNotEmpty) ops.add({'insert': t});
      ops.add({
        'insert': '\n',
        'attributes': {
          'list': item['isChecked'] == true ? 'checked' : 'unchecked'
        }
      });
    }
    for (final a in (m['annotations'] as List? ?? const [])) {
      if (a is Map && a['url'] is String) {
        final title = (a['title'] as String? ?? '').trim();
        ops.add({'insert': title.isEmpty ? '${a['url']}\n' : '$title: ${a['url']}\n'});
      }
    }
    if (ops.isEmpty) ops.add({'insert': '\n'});
    final images = <Uint8List>[];
    for (final a in (m['attachments'] as List? ?? const [])) {
      if (a is! Map) continue;
      final mime = (a['mimetype'] as String? ?? '');
      if (!mime.startsWith('image/')) continue;
      final b = media[_base('${a['filePath']}')];
      if (b != null) images.add(b);
    }
    final title = (m['title'] as String? ?? '').trim();
    notes.add(KeepNote(
      // Vaste id: opnieuw importeren overschrijft in plaats van verdubbelen.
      id: 'keep_${created.microsecondsSinceEpoch}_${title.hashCode & 0xffffff}',
      title: title,
      content: jsonEncode(ops),
      pinned: m['isPinned'] == true,
      archived: m['isArchived'] == true,
      labels: [
        for (final l in (m['labels'] as List? ?? const []))
          if (l is Map && (l['name'] as String? ?? '').trim().isNotEmpty)
            (l['name'] as String).trim()
      ],
      created: created,
      updated: updated,
      images: images,
    ));
  }
  notes.sort((a, b) => b.updated.compareTo(a.updated));
  return KeepImportResult(notes, trashed);
}

/// Zet de geïmporteerde notities in EventFriend. Geeft (notities, foto's).
Future<(int, int)> importKeep(KeepImportResult r, {String space = 'work'}) async {
  var order = store.topOrder;
  var photos = 0;
  for (final k in r.notes.reversed) {
    final id = space == 'work' ? k.id : '${k.id}_$space';
    final existing = store.note(id);
    final n = Note(
      id: id,
      title: k.title,
      text: deltaToPlain(k.content),
      content: k.content,
      created: k.created,
      updated: k.updated,
      pinned: k.pinned,
      archived: k.archived,
      tags: k.labels,
      space: space,
      order: existing?.order ?? order--,
    );
    for (final t in k.labels) {
      await store.addTag(t, space: space);
    }
    await store.importNote(n, k.images);
    photos += k.images.length;
  }
  return (r.notes.length, photos);
}
