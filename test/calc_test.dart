import 'package:eventfriend/calc/bridle.dart';
import 'package:eventfriend/calc/defs.dart';
import 'package:eventfriend/ical.dart';
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
}
