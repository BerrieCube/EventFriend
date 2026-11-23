import 'dart:convert';
import 'dart:typed_data';

import 'package:eventfriend/calc/bridle.dart';
import 'package:eventfriend/calc/defs.dart';
import 'package:eventfriend/format.dart';
import 'package:archive/archive.dart';
import 'package:eventfriend/ical.dart';
import 'package:eventfriend/keep_import.dart';
import 'package:eventfriend/note_text.dart';
import 'package:eventfriend/pdf_theme.dart';
import 'package:eventfriend/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bridle', () {
    test('symmetrisch 90°: 4 m, apex 2 m, 500 kg', () {
      final r = bridle(d: 4, dh: 0, x: 2, h: 2, w: 500);
      expect(r.la, closeTo(2.828, 0.001));
      expect(r.lb, closeTo(2.828, 0.001));
      expect(r.angle, closeTo(90, 0.01));
      expect(r.ta, closeTo(353.6, 0.1));
      expect(r.tb, closeTo(353.6, 0.1));
    });

    test('120° geeft per poot de volle last', () {
      final h = bridleDepthForAngle(d: 4, dh: 0, x: 2, angleDeg: 120);
      final r = bridle(d: 4, dh: 0, x: 2, h: h, w: 500);
      expect(r.angle, closeTo(120, 0.01));
      expect(r.ta, closeTo(500, 0.5));
    });

    test('hoek-modus vindt dezelfde diepte als de formule', () {
      final h = bridleDepthForAngle(d: 4, dh: 0, x: 2, angleDeg: 90);
      expect(h, closeTo(2, 1e-6));
    });

    test('asymmetrisch: verticale krachten tellen op tot de last', () {
      final r = bridle(d: 5, dh: 1, x: 1.5, h: 2, w: 300);
      final va = r.ta * 2 / r.la;
      final vb = r.tb * 3 / r.lb;
      expect(va + vb, closeTo(300, 1e-6));
      final ha = r.ta * 1.5 / r.la;
      final hb = r.tb * 3.5 / r.lb;
      expect(ha, closeTo(hb, 1e-6));
    });

    test('calculator in hoek-modus', () {
      final c = calculators.firstWhere((c) => c.id == 'bridle');
      final o = c.computeWith({'angle': 90, 'd': 4, 'x': 2, 'w': 500});
      expect(o.error, isNull);
      expect(o.steps, isNotEmpty);
      expect(o.extra['h'], closeTo(2, 1e-6));
    });
  });

  test('alle calculators rekenen met standaardwaarden en geven uitleg', () {
    for (final c in calculators) {
      final o = c.computeWith();
      expect(o.error, isNull, reason: c.id);
      expect(o.results, isNotEmpty, reason: c.id);
      expect(o.steps, isNotEmpty, reason: c.id);
    }
  });

  test('LED-wall 6×3 van 500 mm, 192 px', () {
    final c = calculators.firstWhere((c) => c.id == 'ledwall');
    final o = c.computeWith();
    expect(o.results.first.value, '1152 × 576');
  });

  test('DIP-switch 101 = 1 + 4 + 32 + 64', () {
    final c = calculators.firstWhere((c) => c.id == 'dip');
    final o = c.computeWith({'a': 101});
    expect(o.results.first.value, '1, 3, 6, 7');
  });

  test('DMX springt naar volgende universe', () {
    final c = calculators.firstWhere((c) => c.id == 'dmx');
    final o = c.computeWith({'start': 1, 'ch': 100, 'n': 6, 'u': 1});
    expect(o.results[5].value, 'U2 · 1–100');
  });

  test('iCal parser', () {
    const ics = 'BEGIN:VCALENDAR\r\n'
        'BEGIN:VEVENT\r\n'
        'UID:abc-1\r\n'
        'SUMMARY:Congres\\, dag 1\r\n'
        'LOCATION:Jaarbeurs\\, Utrecht\r\n'
        'DESCRIPTION:PM Jan 06-12345678\\nLED-wall\r\n'
        '  6x3\r\n'
        'DTSTART;TZID=Europe/Amsterdam:20261112T083000\r\n'
        'DTEND;TZID=Europe/Amsterdam:20261112T220000\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';
    final e = parseIcal(ics);
    expect(e, hasLength(1));
    expect(e.first.title, 'Congres, dag 1');
    expect(e.first.location, 'Jaarbeurs, Utrecht');
    expect(e.first.description, 'PM Jan 06-12345678\nLED-wall 6x3');
    expect(e.first.start, DateTime(2026, 11, 12, 8, 30));
    expect(normalizeCalendarUrl('webcal://x.nl/a.ics'), 'https://x.nl/a.ics');
  });

  test('notitie-opmaak naar platte tekst', () {
    const delta = '[{"insert":"Inpakken"},{"insert":"\\n","attributes":{"list":"checked"}},'
        '{"insert":"Kabels"},{"insert":"\\n","attributes":{"list":"unchecked"}},'
        '{"insert":"Eerste"},{"insert":"\\n","attributes":{"list":"ordered"}},'
        '{"insert":"Tweede"},{"insert":"\\n","attributes":{"list":"ordered"}},'
        '{"insert":"vet","attributes":{"bold":true}},{"insert":" punt"},'
        '{"insert":"\\n","attributes":{"list":"bullet"}}]';
    expect(deltaToPlain(delta),
        '☑ Inpakken\n☐ Kabels\n1. Eerste\n2. Tweede\n• vet punt');
    expect(deltaToPlain(plainToDelta('Hallo\nwereld')), 'Hallo\nwereld');
  });

  test('weekstart klopt over de wintertijd heen', () {
    // Zondag 25 okt 2026 (klok gaat terug) hoort bij maandag 19 okt.
    expect(weekStart(DateTime(2026, 10, 25, 14)), DateTime(2026, 10, 19));
    expect(weekStart(DateTime(2026, 3, 29, 14)), DateTime(2026, 3, 23));
    final w = weekStart(DateTime(2026, 11, 13));
    expect(DateTime(w.year, w.month, w.day - 7 * 4), DateTime(2026, 10, 12));
    expect(isoWeek(DateTime(2026, 10, 25)), 43);
  });

  test('kW naar kVA en terug', () {
    final c = calculators.firstWhere((c) => c.id == 'kva');
    final o = c.computeWith({'kw': 80, 'pf': 0.8});
    expect(o.results.first.value, '100,0');
    final b = c.computeWith({'kva': 100, 'pf': 0.8}, {'mode': 'kw'});
    expect(b.results.first.value, '80,0');
    expect(b.results[1].value, '60,0'); // kvar
  });

  test('links in tekst herkennen', () {
    final p = splitLinks('Zie https://rentman.io/x. en www.voorbeeld.nl!');
    expect(p.where((e) => e.$2 != null).map((e) => e.$2),
        ['https://rentman.io/x', 'https://www.voorbeeld.nl']);
    expect(p.map((e) => e.$1).join(), 'Zie https://rentman.io/x. en www.voorbeeld.nl!');
  });

  test('klusgegevens bewaren', () {
    final m = JobMeta(id: 'a|1', km: 84, parking: 7.5, costs: 3, costNote: 'tol');
    final r = JobMeta.fromMap(m.toMap());
    expect(r.km, 84);
    expect(r.expenses, 10.5);
    expect(r.invoiced, isNull);
  });

  test('Google Keep-export inlezen', () {
    Uint8List js(Map m) => Uint8List.fromList(utf8.encode(jsonEncode(m)));
    final zip = Archive()
      ..add(ArchiveFile.bytes('Takeout/Keep/Inpaklijst.json', js({
            'title': 'Inpaklijst',
            'textContent': '',
            'isPinned': true,
            'isArchived': false,
            'isTrashed': false,
            'createdTimestampUsec': 1700000000000000,
            'userEditedTimestampUsec': 1700000500000000,
            'labels': [
              {'name': 'Video'}
            ],
            'listContent': [
              {'text': 'SDI-kabels', 'isChecked': true},
              {'text': 'Converter', 'isChecked': false},
            ],
            'attachments': [
              {'filePath': 'abc.jpeg', 'mimetype': 'image/jpeg'}
            ],
          })))
      ..add(ArchiveFile.bytes('Takeout/Keep/abc.jpg', Uint8List.fromList([1, 2, 3])))
      ..add(ArchiveFile.bytes('Takeout/Keep/Weg.json', js({
            'title': 'Weg',
            'textContent': 'x',
            'isTrashed': true,
          })))
      ..add(ArchiveFile.bytes('Takeout/Keep/Wifi.json', js({
            'title': '',
            'textContent': 'Wifi zaal 3: geheim',
            'isArchived': true,
            'createdTimestampUsec': 1600000000000000,
          })));
    final r = parseKeep([('takeout.zip', Uint8List.fromList(ZipEncoder().encode(zip)))]);
    expect(r.notes, hasLength(2));
    expect(r.skippedTrashed, 1);
    final list = r.notes.firstWhere((n) => n.title == 'Inpaklijst');
    expect(list.pinned, isTrue);
    expect(list.labels, ['Video']);
    expect(list.images, hasLength(1)); // .jpeg in json, .jpg in zip
    expect(deltaToPlain(list.content), '☑ SDI-kabels\n☐ Converter');
    final wifi = r.notes.firstWhere((n) => n.title.isEmpty);
    expect(wifi.archived, isTrue);
    expect(deltaToPlain(wifi.content), 'Wifi zaal 3: geheim');
  });

  test('klusnotities horen altijd bij Werk', () {
    final m = Note(
            id: '1',
            text: '',
            created: DateTime(2026),
            updated: DateTime(2026),
            jobKey: 'a|1',
            space: 'private')
        .toMap();
    expect(Note.fromMap(m).space, 'work');
    final loose = Note(
        id: '2',
        text: '',
        created: DateTime(2026),
        updated: DateTime(2026),
        space: 'private');
    expect(Note.fromMap(loose.toMap()).space, 'private');
    expect(Note.fromMap({...loose.toMap()}..remove('space')).space, 'work');
  });

  test('checklist: afvinken, terugzetten en afgevinkte verwijderen', () {
    const d = '[{"insert":"Lijst","attributes":{"bold":true}},{"insert":"\\n"},'
        '{"insert":"A"},{"insert":"\\n","attributes":{"list":"unchecked"}},'
        '{"insert":"B"},{"insert":"\\n","attributes":{"list":"unchecked"}},'
        '{"insert":"C"},{"insert":"\\n","attributes":{"list":"unchecked"}}]';
    final lines = linesOf(d);
    expect(lines.map((l) => l.plain), ['Lijst', 'A', 'B', 'C']);
    expect(lines.first.ops.first['attributes'], {'bold': true});
    // A afvinken: gaat naar het einde.
    final a = setLineChecked(d, 1, true);
    expect(deltaToPlain(a), 'Lijst\n☐ B\n☐ C\n☑ A');
    // A terugzetten: na het laatste open item.
    final b = setLineChecked(a, 3, false);
    expect(deltaToPlain(b), 'Lijst\n☐ B\n☐ C\n☐ A');
    // Afgevinkte weg.
    expect(deltaToPlain(removeCheckedLines(setLineChecked(d, 2, true))),
        'Lijst\n☐ A\n☐ C');
    // Heen en terug zonder wijziging blijft gelijk.
    expect(deltaToPlain(jsonEncode(joinLines(linesOf(d)))), deltaToPlain(d));
  });
}
