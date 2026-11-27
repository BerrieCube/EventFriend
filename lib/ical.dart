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

/// Leest een iCal-agenda (Rentman, Google Agenda, ...). Herhalende
/// afspraken (RRULE) worden uitgeschreven binnen [from]..[to]; losse
/// afspraken houden hun UID zodat gekoppelde notities blijven kloppen.
List<IcalEvent> parseIcal(String text, {DateTime? from, DateTime? to}) {
  final now = DateTime.now();
  from ??= DateTime(now.year, now.month - 6, now.day);
  to ??= DateTime(now.year + 1, now.month + 1, now.day);

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

  // Ruwe VEVENT's verzamelen (onderdelen als VALARM overslaan).
  final raws = <Map<String, List<_Prop>>>[];
  Map<String, List<_Prop>>? cur;
  String? skip;
  for (final line in lines) {
    final upper = line.toUpperCase();
    if (upper == 'BEGIN:VEVENT') {
      cur = {};
      continue;
    }
    if (cur != null && skip == null && upper.startsWith('BEGIN:')) {
      skip = upper.substring(6);
      continue;
    }
    if (skip != null) {
      if (upper == 'END:$skip') skip = null;
      continue;
    }
    if (upper == 'END:VEVENT') {
      if (cur != null) raws.add(cur);
      cur = null;
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
    cur.putIfAbsent(name, () => []).add(_Prop(value, params));
  }

  _Prop? one(Map<String, List<_Prop>> c, String k) => c[k]?.first;

  // Aangepaste keren van een reeks: UID + oorspronkelijke start.
  final overrides = <String, Map<String, List<_Prop>>>{};
  for (final c in raws) {
    final rid = _parseDate(one(c, 'RECURRENCE-ID'));
    final uid = one(c, 'UID')?.value;
    if (rid != null && uid != null) {
      overrides['$uid|${rid.toIso8601String()}'] = c;
    }
  }

  IcalEvent? build(Map<String, List<_Prop>> c, String uid, DateTime start,
      Duration length) {
    if ((one(c, 'STATUS')?.value ?? '').toUpperCase() == 'CANCELLED') {
      return null;
    }
    return IcalEvent(
      uid: uid,
      title: _unescape(one(c, 'SUMMARY')?.value ?? 'Zonder titel'),
      location: _unescape(one(c, 'LOCATION')?.value ?? ''),
      description: _unescape(one(c, 'DESCRIPTION')?.value ?? ''),
      start: start,
      end: start.add(length),
    );
  }

  Duration lengthOf(Map<String, List<_Prop>> c, DateTime start) {
    final dtStart = one(c, 'DTSTART')!;
    final end = _parseDate(one(c, 'DTEND'));
    if (end != null) return end.difference(start);
    final dur = _parseDuration(one(c, 'DURATION')?.value);
    if (dur != null) return dur;
    return dtStart.isDateOnly
        ? DateTime(start.year, start.month, start.day + 1).difference(start)
        : const Duration(hours: 1);
  }

  final events = <IcalEvent>[];
  for (final c in raws) {
    if (one(c, 'RECURRENCE-ID') != null) continue; // via de reeks hieronder
    final start = _parseDate(one(c, 'DTSTART'));
    if (start == null) continue;
    final uid = one(c, 'UID')?.value ??
        '${start.toIso8601String()}-${one(c, 'SUMMARY')?.value}';
    final length = lengthOf(c, start);
    final rrule = one(c, 'RRULE')?.value;
    if (rrule == null) {
      final e = build(c, uid, start, length);
      if (e != null) events.add(e);
      continue;
    }
    final exdates = <DateTime>{
      for (final p in c['EXDATE'] ?? const <_Prop>[])
        for (final v in p.value.split(','))
          if (_parseDate(_Prop(v, p.params)) case final d?) d,
    };
    for (final occ in expandRrule(rrule, start, from, to)) {
      if (exdates.contains(occ)) continue;
      final key = '$uid|${occ.toIso8601String()}';
      final o = overrides[key];
      final occUid = '$uid@${occ.toIso8601String()}';
      if (o != null) {
        final os = _parseDate(one(o, 'DTSTART')) ?? occ;
        final e = build(o, occUid, os, lengthOf(o, os));
        if (e != null) events.add(e);
      } else {
        final e = build(c, occUid, occ, length);
        if (e != null) events.add(e);
      }
    }
  }
  events.sort((a, b) => a.start.compareTo(b.start));
  return events;
}

Duration? _parseDuration(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$')
      .firstMatch(v.trim());
  if (m == null) return null;
  int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  return Duration(
      days: g(1) * 7 + g(2), hours: g(3), minutes: g(4), seconds: g(5));
}

const _wd = {'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7};

/// Schrijft een RRULE uit tot starttijden binnen [from]..[to] (max. 1000).
/// Ondersteunt FREQ DAILY/WEEKLY/MONTHLY/YEARLY met INTERVAL, COUNT, UNTIL,
/// BYDAY (ook 1MO / -1FR bij maandelijks) en BYMONTHDAY.
List<DateTime> expandRrule(
    String rule, DateTime start, DateTime from, DateTime to) {
  final r = <String, String>{};
  for (final part in rule.split(';')) {
    final eq = part.indexOf('=');
    if (eq > 0) r[part.substring(0, eq).toUpperCase()] = part.substring(eq + 1);
  }
  final freq = r['FREQ']?.toUpperCase() ?? 'DAILY';
  final interval = int.tryParse(r['INTERVAL'] ?? '') ?? 1;
  final count = int.tryParse(r['COUNT'] ?? '');
  final until = r['UNTIL'] == null ? null : _parseDate(_Prop(r['UNTIL']!, {}));
  final byDay = (r['BYDAY'] ?? '')
      .split(',')
      .where((x) => x.isNotEmpty)
      .map((x) {
        final m = RegExp(r'^([+-]?\d+)?([A-Z]{2})$').firstMatch(x.toUpperCase());
        return m == null
            ? null
            : (int.tryParse(m.group(1) ?? ''), _wd[m.group(2)]!);
      })
      .whereType<(int?, int)>()
      .toList();
  final byMonthDay = (r['BYMONTHDAY'] ?? '')
      .split(',')
      .map(int.tryParse)
      .whereType<int>()
      .toList();

  DateTime at(int y, int mo, int d) =>
      DateTime(y, mo, d, start.hour, start.minute, start.second);
  final out = <DateTime>[];
  var n = 0; // aantal keren (voor COUNT, telt vanaf de start)

  bool add(DateTime d) {
    if (d.isBefore(start)) return true;
    if (until != null && d.isAfter(until)) return false;
    if (count != null && n >= count) return false;
    n++;
    if (d.isAfter(to)) return false;
    if (!d.isBefore(from)) out.add(d);
    return out.length < 1000;
  }

  for (var i = 0; i < 5000; i++) {
    List<DateTime> cands;
    switch (freq) {
      case 'WEEKLY':
        final weekStart = DateTime(start.year, start.month,
            start.day - (start.weekday - 1) + 7 * interval * i);
        final days = byDay.isEmpty ? [start.weekday] : byDay.map((b) => b.$2);
        cands = [
          for (final wd in days)
            at(weekStart.year, weekStart.month, weekStart.day + wd - 1)
        ]..sort();
      case 'MONTHLY':
        final y = start.year, mo = start.month + interval * i;
        final first = DateTime(y, mo, 1);
        final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
        if (byDay.isNotEmpty) {
          cands = [];
          for (final (nth, wd) in byDay) {
            final all = [
              for (var d = 1; d <= daysInMonth; d++)
                if (DateTime(first.year, first.month, d).weekday == wd) d
            ];
            final pick = nth == null
                ? all
                : nth > 0
                    ? (nth <= all.length ? [all[nth - 1]] : <int>[])
                    : (-nth <= all.length ? [all[all.length + nth]] : <int>[]);
            cands.addAll(pick.map((d) => at(first.year, first.month, d)));
          }
          cands.sort();
        } else {
          final days = byMonthDay.isEmpty ? [start.day] : byMonthDay;
          cands = [
            for (final d in days)
              if ((d > 0 ? d : daysInMonth + d + 1) <= daysInMonth)
                at(first.year, first.month, d > 0 ? d : daysInMonth + d + 1)
          ]..sort();
        }
      case 'YEARLY':
        final y = start.year + interval * i;
        final daysInMonth = DateTime(y, start.month + 1, 0).day;
        cands = start.day <= daysInMonth ? [at(y, start.month, start.day)] : [];
      default: // DAILY
        cands = [at(start.year, start.month, start.day + interval * i)];
    }
    for (final d in cands) {
      if (!add(d)) return out;
    }
  }
  return out;
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
