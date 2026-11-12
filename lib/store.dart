/// Lokale opslag (werkt offline, op Android en in de browser).
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'ical.dart';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

Map<String, dynamic> _m(dynamic v) => Map<String, dynamic>.from(v as Map);

class CalendarSource {
  final String id;
  String name;
  String url;
  DateTime? lastSync;
  String? error;

  CalendarSource(
      {required this.id,
      required this.name,
      required this.url,
      this.lastSync,
      this.error});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'url': url,
        'lastSync': lastSync?.toIso8601String(),
        'error': error,
      };

  factory CalendarSource.fromMap(Map<String, dynamic> m) => CalendarSource(
        id: m['id'],
        name: m['name'],
        url: m['url'],
        lastSync: m['lastSync'] == null ? null : DateTime.parse(m['lastSync']),
        error: m['error'],
      );
}

class Job {
  final String key; // calId|uid
  final String calId;
  String title;
  String location;
  String description;
  DateTime start;
  DateTime end;

  Job(
      {required this.key,
      required this.calId,
      required this.title,
      required this.location,
      required this.description,
      required this.start,
      required this.end});

  bool get isManual => calId == 'manual';

  Map<String, dynamic> toMap() => {
        'key': key,
        'calId': calId,
        'title': title,
        'location': location,
        'description': description,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      };

  factory Job.fromMap(Map<String, dynamic> m) => Job(
        key: m['key'],
        calId: m['calId'],
        title: m['title'],
        location: m['location'] ?? '',
        description: m['description'] ?? '',
        start: DateTime.parse(m['start']),
        end: DateTime.parse(m['end']),
      );

  /// Telefoonnummers uit de omschrijving (Rentman zet contactgegevens vaak daar).
  List<String> get phoneNumbers {
    final re = RegExp(r'(\+?\d[\d \-]{7,}\d)');
    return re
        .allMatches(description)
        .map((m) => m.group(1)!.replaceAll(RegExp(r'[ \-]'), ''))
        .where((n) => n.length >= 9 && n.length <= 15)
        .toSet()
        .toList();
  }
}

class Note {
  final String id;
  String text;
  String? jobKey;
  String? jobTitle;
  DateTime created;
  DateTime updated;

  Note(
      {required this.id,
      required this.text,
      this.jobKey,
      this.jobTitle,
      required this.created,
      required this.updated});

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'jobKey': jobKey,
        'jobTitle': jobTitle,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
      };

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'],
        text: m['text'] ?? '',
        jobKey: m['jobKey'],
        jobTitle: m['jobTitle'],
        created: DateTime.parse(m['created']),
        updated: DateTime.parse(m['updated']),
      );
}

class Photo {
  final String id;
  final String jobKey;
  String caption;
  final DateTime created;
  final Uint8List bytes;

  Photo(
      {required this.id,
      required this.jobKey,
      required this.caption,
      required this.created,
      required this.bytes});

  Map<String, dynamic> toMap() => {
        'id': id,
        'jobKey': jobKey,
        'caption': caption,
        'created': created.toIso8601String(),
        'bytes': bytes,
      };

  factory Photo.fromMap(Map<String, dynamic> m) => Photo(
        id: m['id'],
        jobKey: m['jobKey'],
        caption: m['caption'] ?? '',
        created: DateTime.parse(m['created']),
        bytes: m['bytes'] as Uint8List,
      );
}

class TimeEntry {
  final String id;
  DateTime start;
  DateTime? end;
  int pauseMin;
  double km;
  String? jobKey;
  String jobTitle;
  String note;

  TimeEntry(
      {required this.id,
      required this.start,
      this.end,
      this.pauseMin = 0,
      this.km = 0,
      this.jobKey,
      this.jobTitle = '',
      this.note = ''});

  bool get running => end == null;

  Duration get worked {
    final e = end ?? DateTime.now();
    final d = e.difference(start) - Duration(minutes: pauseMin);
    return d.isNegative ? Duration.zero : d;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'pauseMin': pauseMin,
        'km': km,
        'jobKey': jobKey,
        'jobTitle': jobTitle,
        'note': note,
      };

  factory TimeEntry.fromMap(Map<String, dynamic> m) => TimeEntry(
        id: m['id'],
        start: DateTime.parse(m['start']),
        end: m['end'] == null ? null : DateTime.parse(m['end']),
        pauseMin: (m['pauseMin'] ?? 0) as int,
        km: ((m['km'] ?? 0) as num).toDouble(),
        jobKey: m['jobKey'],
        jobTitle: m['jobTitle'] ?? '',
        note: m['note'] ?? '',
      );
}

class Store extends ChangeNotifier {
  late Box _cals, _jobs, _notes, _photos, _hours, _calc;
  bool syncing = false;

  Future<void> init() async {
    await Hive.initFlutter();
    _cals = await Hive.openBox('calendars');
    _jobs = await Hive.openBox('jobs');
    _notes = await Hive.openBox('notes');
    _photos = await Hive.openBox('photos');
    _hours = await Hive.openBox('hours');
    _calc = await Hive.openBox('calc');
  }

  // ---------- Laatst gebruikte invoer van calculators ----------
  Map<String, String> calcInputs(String id) {
    final v = _calc.get(id);
    return v == null ? {} : Map<String, String>.from(v as Map);
  }

  Future<void> saveCalcInputs(String id, Map<String, String> v) =>
      _calc.put(id, v);

  // ---------- Kalenders ----------
  List<CalendarSource> get calendars =>
      _cals.values.map((v) => CalendarSource.fromMap(_m(v))).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  CalendarSource? calendar(String id) {
    final v = _cals.get(id);
    return v == null ? null : CalendarSource.fromMap(_m(v));
  }

  Future<CalendarSource> addCalendar(String name, String url) async {
    final c = CalendarSource(
        id: newId(), name: name, url: normalizeCalendarUrl(url));
    await _cals.put(c.id, c.toMap());
    notifyListeners();
    await syncCalendar(c);
    return c;
  }

  Future<void> updateCalendar(CalendarSource c) async {
    c.url = normalizeCalendarUrl(c.url);
    await _cals.put(c.id, c.toMap());
    notifyListeners();
  }

  Future<void> removeCalendar(String id) async {
    await _cals.delete(id);
    final keys = _jobs.keys
        .where((k) => _m(_jobs.get(k))['calId'] == id)
        .toList();
    await _jobs.deleteAll(keys);
    notifyListeners();
  }

  Future<void> syncAll() async {
    if (syncing) return;
    syncing = true;
    notifyListeners();
    for (final c in calendars) {
      await syncCalendar(c, notify: false);
    }
    syncing = false;
    notifyListeners();
  }

  Future<void> syncCalendar(CalendarSource c, {bool notify = true}) async {
    try {
      final res = await http
          .get(Uri.parse(c.url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw Exception('Server gaf status ${res.statusCode}');
      }
      final body = res.body;
      if (!body.contains('BEGIN:VCALENDAR')) {
        throw Exception('Dit lijkt geen iCal-agenda te zijn');
      }
      final events = parseIcal(body);
      final old = _jobs.keys
          .where((k) => _m(_jobs.get(k))['calId'] == c.id)
          .toList();
      await _jobs.deleteAll(old);
      final entries = <String, dynamic>{};
      for (final e in events) {
        final key = '${c.id}|${e.uid}';
        entries[key] = Job(
          key: key,
          calId: c.id,
          title: e.title,
          location: e.location,
          description: e.description,
          start: e.start,
          end: e.end,
        ).toMap();
      }
      await _jobs.putAll(entries);
      c.lastSync = DateTime.now();
      c.error = null;
    } catch (e) {
      c.error = kIsWeb
          ? 'Ophalen lukt niet in de browser (de agenda-server blokkeert dit). '
              'In de Android-app werkt het wel. ($e)'
          : 'Ophalen mislukt: $e';
    }
    await _cals.put(c.id, c.toMap());
    if (notify) notifyListeners();
  }

  // ---------- Klussen ----------
  List<Job> get jobs =>
      _jobs.values.map((v) => Job.fromMap(_m(v))).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  Job? job(String? key) {
    if (key == null) return null;
    final v = _jobs.get(key);
    return v == null ? null : Job.fromMap(_m(v));
  }

  List<Job> jobsOn(DateTime day) {
    final s = DateTime(day.year, day.month, day.day);
    final e = s.add(const Duration(days: 1));
    return jobs.where((j) => j.start.isBefore(e) && j.end.isAfter(s)).toList();
  }

  Future<void> saveManualJob(Job j) async {
    await _jobs.put(j.key, j.toMap());
    notifyListeners();
  }

  Future<void> deleteJob(String key) async {
    await _jobs.delete(key);
    notifyListeners();
  }

  // ---------- Notities ----------
  List<Note> get notes => _notes.values.map((v) => Note.fromMap(_m(v))).toList()
    ..sort((a, b) => b.updated.compareTo(a.updated));

  List<Note> notesFor(String jobKey) =>
      notes.where((n) => n.jobKey == jobKey).toList()
        ..sort((a, b) => a.created.compareTo(b.created));

  Future<void> saveNote(Note n) async {
    n.updated = DateTime.now();
    await _notes.put(n.id, n.toMap());
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    await _notes.delete(id);
    notifyListeners();
  }

  // ---------- Foto's ----------
  List<Photo> photosFor(String jobKey) => _photos.values
      .map((v) => Photo.fromMap(_m(v)))
      .where((p) => p.jobKey == jobKey)
      .toList()
    ..sort((a, b) => a.created.compareTo(b.created));

  Future<void> addPhoto(String jobKey, Uint8List bytes) async {
    final p = Photo(
        id: newId(),
        jobKey: jobKey,
        caption: '',
        created: DateTime.now(),
        bytes: bytes);
    await _photos.put(p.id, p.toMap());
    notifyListeners();
  }

  Future<void> savePhoto(Photo p) async {
    await _photos.put(p.id, p.toMap());
    notifyListeners();
  }

  Future<void> deletePhoto(String id) async {
    await _photos.delete(id);
    notifyListeners();
  }

  // ---------- Uren ----------
  List<TimeEntry> get hours =>
      _hours.values.map((v) => TimeEntry.fromMap(_m(v))).toList()
        ..sort((a, b) => b.start.compareTo(a.start));

  TimeEntry? get running {
    for (final h in hours) {
      if (h.running) return h;
    }
    return null;
  }

  Future<void> clockIn({Job? job}) async {
    if (running != null) return;
    final t = TimeEntry(
        id: newId(),
        start: DateTime.now(),
        jobKey: job?.key,
        jobTitle: job?.title ?? '');
    await _hours.put(t.id, t.toMap());
    notifyListeners();
  }

  Future<void> clockOut() async {
    final r = running;
    if (r == null) return;
    r.end = DateTime.now();
    await _hours.put(r.id, r.toMap());
    notifyListeners();
  }

  Future<void> saveEntry(TimeEntry t) async {
    await _hours.put(t.id, t.toMap());
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    await _hours.delete(id);
    notifyListeners();
  }
}

final store = Store();
