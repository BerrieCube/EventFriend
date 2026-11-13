/// Eenvoudige iCal (.ics) parser voor Rentman-agenda's.
library;

class IcalEvent {
  final String uid;
  final String title;
  final String location;
  final String description;
  final DateTime start;
  final DateTime end;

  IcalEvent({
    required this.uid,
    required this.title,
    required this.location,
    required this.description,
    required this.start,
    required this.end,
  });
}

/// webcal:// links omzetten naar https://
String normalizeCalendarUrl(String url) {
  var u = url.trim();
  if (u.toLowerCase().startsWith('webcal://')) {
    u = 'https://${u.substring(9)}';
  }
  return u;
}

List<IcalEvent> parseIcal(String text) {
  // Regels "unfolden": een regel die met spatie of tab begint hoort bij de vorige.
  final raw = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final lines = <String>[];
  for (final l in raw) {
    if ((l.startsWith(' ') || l.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] += l.substring(1);
    } else {
      lines.add(l);
    }
  }

  final events = <IcalEvent>[];
  Map<String, _Prop>? cur;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      cur = {};
      continue;
    }
    if (line == 'END:VEVENT') {
      final c = cur;
      cur = null;
      if (c == null) continue;
      final start = _parseDate(c['DTSTART']);
      if (start == null) continue;
      var end = _parseDate(c['DTEND']) ?? start.add(const Duration(hours: 1));
      if (c['DTSTART']!.isDateOnly && c['DTEND'] == null) {
        end = DateTime(start.year, start.month, start.day + 1);
      }
      events.add(IcalEvent(
        uid: c['UID']?.value ?? '${start.toIso8601String()}-${c['SUMMARY']?.value}',
        title: _unescape(c['SUMMARY']?.value ?? 'Zonder titel'),
        location: _unescape(c['LOCATION']?.value ?? ''),
        description: _unescape(c['DESCRIPTION']?.value ?? ''),
        start: start,
        end: end,
      ));
      continue;
    }
    if (cur == null) continue;
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final left = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final parts = left.split(';');
    final name = parts.first.toUpperCase();
    final params = <String, String>{};
    for (final p in parts.skip(1)) {
      final eq = p.indexOf('=');
      if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1);
    }
    cur[name] = _Prop(value, params);
  }
  events.sort((a, b) => a.start.compareTo(b.start));
  return events;
}

class _Prop {
  final String value;
  final Map<String, String> params;
  _Prop(this.value, this.params);
  bool get isDateOnly =>
      params['VALUE'] == 'DATE' || RegExp(r'^\d{8}$').hasMatch(value.trim());
}

DateTime? _parseDate(_Prop? p) {
  if (p == null) return null;
  final v = p.value.trim();
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$')
      .firstMatch(v);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (m.group(4) == null) return DateTime(y, mo, d);
  final h = int.parse(m.group(4)!);
  final mi = int.parse(m.group(5)!);
  final s = int.tryParse(m.group(6) ?? '0') ?? 0;
  if (m.group(7) == 'Z') {
    return DateTime.utc(y, mo, d, h, mi, s).toLocal();
  }
  // Met TZID of "floating": we gaan uit van de lokale tijd van de telefoon.
  return DateTime(y, mo, d, h, mi, s);
}

String _unescape(String s) => s
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\');
