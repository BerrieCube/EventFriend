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
  String title; // mag leeg zijn
  String text; // platte tekst (afgeleid van content), voor zoeken en melding
  String? content; // opgemaakte inhoud (Quill Delta JSON)
  String? jobKey;
  String? jobTitle;
  DateTime created;
  DateTime updated;
  bool lockscreen; // tonen als vaste melding op het vergrendelscherm
  bool widget; // tonen in de notitie-widget op het startscherm
  bool pinned; // bovenaan vastgezet
  List<String> tags;
  double order; // handmatige volgorde (lager = hoger in de lijst)

  Note(
      {required this.id,
      required this.text,
      this.title = '',
      this.content,
      this.jobKey,
      this.jobTitle,
      required this.created,
      required this.updated,
      this.lockscreen = false,
      this.widget = false,
      this.pinned = false,
      List<String>? tags,
      double? order})
      : tags = tags ?? [],
        order = order ?? -created.millisecondsSinceEpoch.toDouble();

  /// Kop voor lijsten en meldingen: titel, anders eerste regel.
  String get heading {
    if (title.trim().isNotEmpty) return title.trim();
    final first = text.trim().split('\n').first;
    return first.isEmpty ? 'Notitie' : first;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'jobKey': jobKey,
        'jobTitle': jobTitle,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
        'lockscreen': lockscreen,
        'widget': widget,
        'title': title,
        'content': content,
        'pinned': pinned,
        'tags': tags,
        'order': order,
      };

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'],
        text: m['text'] ?? '',
        jobKey: m['jobKey'],
        jobTitle: m['jobTitle'],
        created: DateTime.parse(m['created']),
        updated: DateTime.parse(m['updated']),
        lockscreen: m['lockscreen'] == true,
        widget: m['widget'] == true,
        title: m['title'] ?? '',
        content: m['content'],
        pinned: m['pinned'] == true,
        tags: (m['tags'] as List?)?.map((e) => '$e').toList(),
        order: (m['order'] as num?)?.toDouble(),
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

class Doc {
  final String id;
  String type; // 'file' of 'link'
  String name;
  String? url; // bij links
  String mime;
  int size;
  String? jobKey; // null = bibliotheek (Tools)
  DateTime created;
  DateTime? deleteAfter; // callsheets: 30 dagen na de klus
  Uint8List? bytes;

  Doc(
      {required this.id,
      required this.type,
      required this.name,
      this.url,
      this.mime = '',
      this.size = 0,
      this.jobKey,
      required this.created,
      this.deleteAfter,
      this.bytes});

  bool get isLink => type == 'link';
  bool get isPdf =>
      mime == 'application/pdf' || name.toLowerCase().endsWith('.pdf');

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'name': name,
        'url': url,
        'mime': mime,
        'size': size,
        'jobKey': jobKey,
        'created': created.toIso8601String(),
        'deleteAfter': deleteAfter?.toIso8601String(),
        'bytes': bytes,
      };

  factory Doc.fromMap(Map<String, dynamic> m) => Doc(
        id: m['id'],
        type: m['type'] ?? 'file',
        name: m['name'] ?? '',
        url: m['url'],
        mime: m['mime'] ?? '',
        size: (m['size'] ?? 0) as int,
        jobKey: m['jobKey'],
        created: DateTime.parse(m['created']),
        deleteAfter:
            m['deleteAfter'] == null ? null : DateTime.parse(m['deleteAfter']),
        bytes: m['bytes'] as Uint8List?,
      );
}

/// Bewaartermijn van callsheets na afloop van de klus.
const docRetention = Duration(days: 30);

String mimeFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (n.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (n.endsWith('.txt')) return 'text/plain';
  return 'application/octet-stream';
}

class AppTile {
  final String id;
  String type; // 'app' (Android-app) of 'link'
  String name;
  String? package; // bij apps
  String? url; // bij links (bijv. Spotify-playlist)
  String section; // 'Algemeen' of een Tools-onderdeel
  double order;

  AppTile(
      {required this.id,
      required this.type,
      required this.name,
      this.package,
      this.url,
      this.section = 'Algemeen',
      this.order = 0});

  bool get isApp => type == 'app';

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'name': name,
        'package': package,
        'url': url,
        'section': section,
        'order': order,
      };

  factory AppTile.fromMap(Map<String, dynamic> m) => AppTile(
        id: m['id'],
        type: m['type'] ?? 'link',
        name: m['name'] ?? '',
        package: m['package'],
        url: m['url'],
        section: m['section'] ?? 'Algemeen',
        order: ((m['order'] ?? 0) as num).toDouble(),
      );
}

/// Eigen gegevens bij een klus (ook bij Rentman-klussen, die zelf
/// alleen-lezen zijn): gefactureerd, kilometers en onkosten.
class JobMeta {
  final String id; // = sleutel van de klus
  DateTime? invoiced;
  double km;
  double parking;
  double costs;
  String costNote;

  JobMeta(
      {required this.id,
      this.invoiced,
      this.km = 0,
      this.parking = 0,
      this.costs = 0,
      this.costNote = ''});

  double get expenses => parking + costs;

  Map<String, dynamic> toMap() => {
        'id': id,
        'invoiced': invoiced?.toIso8601String(),
        'km': km,
        'parking': parking,
        'costs': costs,
        'costNote': costNote,
      };

  factory JobMeta.fromMap(Map<String, dynamic> m) => JobMeta(
        id: m['id'],
        invoiced:
            m['invoiced'] == null ? null : DateTime.parse(m['invoiced']),
        km: ((m['km'] ?? 0) as num).toDouble(),
        parking: ((m['parking'] ?? 0) as num).toDouble(),
        costs: ((m['costs'] ?? 0) as num).toDouble(),
        costNote: m['costNote'] ?? '',
      );
}

class Store extends ChangeNotifier {
  late Box _cals, _jobs, _notes, _photos, _hours, _calc, _sync, _docs, _apps,
      _meta, _prefs;

  /// Wordt aangeroepen na elke lokale wijziging (voor automatisch synchroniseren).
  VoidCallback? onLocalChange;

  /// Haalt een agenda op via de server (webversie). Gezet door de sync-service.
  Future<String> Function(String url)? remoteIcalFetch;
  bool syncing = false;

  Future<void> init() async {
    await Hive.initFlutter();
    _cals = await Hive.openBox('calendars');
    _jobs = await Hive.openBox('jobs');
    _notes = await Hive.openBox('notes');
    _photos = await Hive.openBox('photos');
    _hours = await Hive.openBox('hours');
    _calc = await Hive.openBox('calc');
    _sync = await Hive.openBox('sync');
    _docs = await Hive.openBox('docs');
    _apps = await Hive.openBox('apps');
    _meta = await Hive.openBox('jobmeta');
    _prefs = await Hive.openBox('prefs');
    await _repairHours();
  }

  /// Een oudere app-versie zette onbekende soorten (zoals 'jobmeta') bij de
  /// uren. Die worden opgeruimd en daarna wordt alles opnieuw opgehaald.
  Future<void> _repairHours() async {
    final bad = _hours.keys.where((k) {
      final v = _hours.get(k);
      return v is! Map || v['start'] == null;
    }).toList();
    if (bad.isEmpty) return;
    await _hours.deleteAll(bad);
    await _sync.delete('lastPull');
  }

  // ---------- Instellingen (gesynchroniseerd) ----------
  dynamic pref(String key, [dynamic def]) {
    final v = _prefs.get(key);
    return v == null ? def : _m(v)['v'] ?? def;
  }

  Future<void> setPref(String key, dynamic value) =>
      _put('setting', key, {'v': value});

  String get homeAddress => pref('home', '') as String;

  /// Minuten vóór de start van een klus voor de calltime-herinnering (0 = uit).
  int get reminderMinutes => (pref('reminder', 0) as num).toInt();

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
    await _put('calendar', c.id, c.toMap());
    await syncCalendar(c);
    return c;
  }

  Future<void> updateCalendar(CalendarSource c) async {
    c.url = normalizeCalendarUrl(c.url);
    await _put('calendar', c.id, c.toMap());
  }

  Future<void> removeCalendar(String id) async {
    await _del('calendar', id);
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
      final String body;
      if (kIsWeb) {
        final f = remoteIcalFetch;
        if (f == null) {
          throw Exception('Log in (tandwiel → Account) om agenda\'s in de browser op te halen.');
        }
        body = await f(c.url).timeout(const Duration(seconds: 30));
      } else {
        final res = await http
            .get(Uri.parse(c.url))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          throw Exception('Server gaf status ${res.statusCode}');
        }
        body = res.body;
      }
      if (!body.contains('BEGIN:VCALENDAR')) {
        throw Exception('Dit lijkt geen iCal-agenda te zijn');
      }
      final events = parseIcal(body);
      // Afgelopen klussen die uit de feed verdwijnen (Rentman toont vaak
      // maar een beperkte periode) blijven bewaard voor je administratie.
      final now = DateTime.now();
      final old = _jobs.keys.where((k) {
        final m = _m(_jobs.get(k));
        return m['calId'] == c.id && !DateTime.parse(m['end']).isBefore(now);
      }).toList();
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
      c.error = 'Ophalen mislukt: ${e.toString().replaceFirst('Exception: ', '')}';
    }
    await _cals.put(c.id, c.toMap());
    if (notify) notifyListeners();
  }

  // ---------- Klussen ----------
  /// Naam van de opdrachtgever (= naam van de agenda) of "Eigen klus".
  String clientName(Job j) =>
      j.isManual ? 'Eigen klus' : (calendar(j.calId)?.name ?? 'Onbekend');

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
    final e = DateTime(s.year, s.month, s.day + 1);
    return jobs.where((j) => j.start.isBefore(e) && j.end.isAfter(s)).toList();
  }

  // ---------- Facturatie, kilometers en onkosten ----------
  JobMeta meta(String jobKey) {
    final v = _meta.get(jobKey);
    return v == null ? JobMeta(id: jobKey) : JobMeta.fromMap(_m(v));
  }

  Future<void> saveMeta(JobMeta m) => _put('jobmeta', m.id, m.toMap());

  bool isInvoiced(Job j) => meta(j.key).invoiced != null;

  Future<void> setInvoiced(Iterable<Job> jobs, bool invoiced) async {
    final t = DateTime.now();
    for (final j in jobs) {
      final m = meta(j.key);
      if ((m.invoiced != null) == invoiced) continue;
      m.invoiced = invoiced ? t : null;
      await saveMeta(m);
    }
  }

  /// Kilometers voor een klus: ingevuld bij de klus plus eventueel bij de uren.
  double kmFor(Job j) =>
      meta(j.key).km +
      hours.where((h) => h.jobKey == j.key).fold(0.0, (s, h) => s + h.km);

  /// Afgelopen klussen die nog niet gefactureerd zijn.
  List<Job> get toProcess {
    final now = DateTime.now();
    return jobs.where((j) => !j.end.isAfter(now) && !isInvoiced(j)).toList();
  }

  Future<void> saveManualJob(Job j) => _put('job', j.key, j.toMap());

  Future<void> deleteJob(String key) => _del('job', key);

  // ---------- Notities ----------
  /// Vastgezet eerst, daarna handmatige volgorde.
  List<Note> get notes => _notes.values.map((v) => Note.fromMap(_m(v))).toList()
    ..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return a.order.compareTo(b.order);
    });

  /// Alle gebruikte tags plus zelf aangemaakte (nog lege) tags.
  List<String> get allTags {
    final t = <String>{
      for (final n in notes) ...n.tags,
      ...List<String>.from((_sync.get('extraTags') ?? const []) as List),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return t;
  }

  Future<void> addTag(String tag) async {
    final l = List<String>.from((_sync.get('extraTags') ?? const []) as List);
    if (!l.contains(tag)) {
      l.add(tag);
      await _sync.put('extraTags', l);
      notifyListeners();
    }
  }

  Future<void> removeTag(String tag) async {
    final l = List<String>.from((_sync.get('extraTags') ?? const []) as List)
      ..remove(tag);
    await _sync.put('extraTags', l);
    for (final n in notes.where((n) => n.tags.contains(tag))) {
      n.tags.remove(tag);
      await saveNote(n, touch: false);
    }
    notifyListeners();
  }

  /// Notitie hoort bij een klus die voorbij is.
  bool isPastJobNote(Note n) {
    final j = job(n.jobKey);
    return j != null && j.end.isBefore(DateTime.now());
  }

  List<Note> notesFor(String jobKey) =>
      notes.where((n) => n.jobKey == jobKey).toList()
        ..sort((a, b) => a.created.compareTo(b.created));

  Future<void> saveNote(Note n, {bool touch = true}) async {
    if (touch) n.updated = DateTime.now();
    await _put('note', n.id, n.toMap());
  }

  Future<void> deleteNote(String id) => _del('note', id);

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
    await _put('photo', p.id, p.toMap());
  }

  Future<void> savePhoto(Photo p) => _put('photo', p.id, p.toMap());

  Future<void> deletePhoto(String id) => _del('photo', id);

  // ---------- Documenten en links ----------
  List<Doc> get _allDocs => _docs.values.map((v) => Doc.fromMap(_m(v))).toList();

  List<Doc> docsFor(String jobKey) =>
      _allDocs.where((d) => d.jobKey == jobKey).toList()
        ..sort((a, b) => a.created.compareTo(b.created));

  List<Doc> get libraryDocs => _allDocs.where((d) => d.jobKey == null).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Uint8List? docBytes(String id) {
    final v = _docs.get(id);
    return v == null ? null : _m(v)['bytes'] as Uint8List?;
  }

  Future<void> addFile(String name, Uint8List bytes, {Job? job}) async {
    final d = Doc(
      id: newId(),
      type: 'file',
      name: name,
      mime: mimeFor(name),
      size: bytes.length,
      jobKey: job?.key,
      created: DateTime.now(),
      deleteAfter: job == null ? null : job.end.add(docRetention),
      bytes: bytes,
    );
    await _put('doc', d.id, d.toMap());
  }

  Future<void> addLink(String name, String url) async {
    var u = url.trim();
    if (!u.contains('://')) u = 'https://$u';
    final d = Doc(
        id: newId(), type: 'link', name: name, url: u, created: DateTime.now());
    await _put('doc', d.id, d.toMap());
  }

  Future<void> saveDoc(Doc d) => _put('doc', d.id, d.toMap());

  Future<void> deleteDoc(String id) => _del('doc', id);

  /// Callsheets 30 dagen na de klus automatisch verwijderen.
  Future<int> cleanupExpiredDocs() async {
    final now = DateTime.now();
    final expired = _allDocs
        .where((d) => d.deleteAfter != null && d.deleteAfter!.isBefore(now))
        .toList();
    for (final d in expired) {
      await _del('doc', d.id);
    }
    return expired.length;
  }

  // ---------- App- en link-tegels (Tools) ----------
  List<AppTile> appsIn(String section) => _apps.values
      .map((v) => AppTile.fromMap(_m(v)))
      .where((a) => a.section == section)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  Future<void> saveApp(AppTile a) => _put('app', a.id, a.toMap());

  Future<void> deleteApp(String id) => _del('app', id);

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
    await _put('hours', t.id, t.toMap());
  }

  Future<void> clockOut() async {
    final r = running;
    if (r == null) return;
    r.end = DateTime.now();
    await _put('hours', r.id, r.toMap());
  }

  Future<void> saveEntry(TimeEntry t) => _put('hours', t.id, t.toMap());

  Future<void> deleteEntry(String id) => _del('hours', id);

  // ---------- Synchronisatie (gebruikt door sync.dart) ----------
  static const kinds = [
    'calendar', 'job', 'note', 'photo', 'hours', 'doc', 'app', 'jobmeta',
    'setting'
  ];

  Box _box(String kind) => switch (kind) {
        'calendar' => _cals,
        'job' => _jobs,
        'note' => _notes,
        'photo' => _photos,
        'doc' => _docs,
        'app' => _apps,
        'jobmeta' => _meta,
        'setting' => _prefs,
        _ => _hours,
      };

  /// Openstaande lokale wijzigingen: "kind|id" -> tijdstip van wijzigen.
  Map<String, String> get dirty =>
      Map<String, String>.from((_sync.get('dirty') ?? {}) as Map);

  Future<void> _setDirty(Map<String, String> d) => _sync.put('dirty', d);

  Future<void> _put(String kind, String id, Map<String, dynamic> m) async {
    await _box(kind).put(id, m);
    await _setDirty(dirty..['$kind|$id'] = DateTime.now().toUtc().toIso8601String());
    notifyListeners();
    onLocalChange?.call();
  }

  Future<void> _del(String kind, String id) async {
    await _box(kind).delete(id);
    await _setDirty(dirty..['$kind|$id'] = DateTime.now().toUtc().toIso8601String());
    notifyListeners();
    onLocalChange?.call();
  }

  /// Lokale gegevens als record voor de server (null = verwijderd).
  Map<String, dynamic>? localRecord(String kind, String id) {
    final v = _box(kind).get(id);
    if (v == null) return null;
    final m = _m(v);
    if (kind == 'photo' || kind == 'doc') m.remove('bytes');
    if (kind == 'calendar') {
      m.remove('lastSync');
      m.remove('error');
    }
    return m;
  }

  Uint8List? photoBytes(String id) {
    final v = _photos.get(id);
    return v == null ? null : _m(v)['bytes'] as Uint8List?;
  }

  bool hasLocal(String kind, String id) => _box(kind).containsKey(id);

  Future<void> clearDirty(String key, String stamp) async {
    final d = dirty;
    if (d[key] == stamp) {
      d.remove(key);
      await _setDirty(d);
    }
  }

  /// Wijziging van de server toepassen zonder hem opnieuw als "dirty" te markeren.
  Future<void> applyRemote(String kind, String id, Map<String, dynamic>? data,
      {Uint8List? bytes}) async {
    if (!kinds.contains(kind)) return; // nieuwere app-versie: overslaan
    final box = _box(kind);
    if (data == null) {
      await box.delete(id);
      if (kind == 'calendar') {
        final keys =
            _jobs.keys.where((k) => _m(_jobs.get(k))['calId'] == id).toList();
        await _jobs.deleteAll(keys);
      }
      return;
    }
    final m = Map<String, dynamic>.from(data);
    if (kind == 'calendar') {
      final old = box.get(id);
      if (old != null) {
        final o = _m(old);
        m['lastSync'] = o['lastSync'];
        m['error'] = o['error'];
      }
    }
    if (kind == 'photo') {
      final b = bytes ?? photoBytes(id);
      if (b == null) return;
      m['bytes'] = b;
    }
    if (kind == 'doc' && m['type'] != 'link') {
      final b = bytes ?? docBytes(id);
      if (b == null) return;
      m['bytes'] = b;
    }
    await box.put(id, m);
  }

  /// Alle lokale gegevens markeren om te uploaden (bij eerste keer inloggen).
  Future<void> markAllDirty() async {
    final d = dirty;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final k in kinds) {
      for (final id in _box(k).keys) {
        if (k == 'job' && !(id as String).startsWith('manual|')) continue;
        d.putIfAbsent('$k|$id', () => now);
      }
    }
    await _setDirty(d);
  }

  String? get lastPull => _sync.get('lastPull') as String?;
  Future<void> setLastPull(String? v) => _sync.put('lastPull', v);
  DateTime? get lastSyncTime {
    final v = _sync.get('lastSyncTime') as String?;
    return v == null ? null : DateTime.parse(v);
  }

  Future<void> setLastSyncTime(DateTime t) =>
      _sync.put('lastSyncTime', t.toIso8601String());

  void refresh() => notifyListeners();
}

final store = Store();
