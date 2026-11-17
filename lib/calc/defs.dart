/// Alle calculators. Elke berekening schrijft zijn stappen weg zodat je
/// in de app kunt nalezen hoe de uitkomst tot stand komt.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../format.dart';
import 'bridle.dart';
import 'bridle_diagram.dart';
import 'calc.dart';

String f(double v, [int d = 2]) => nf(v, d);

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

const g = 9.81;
const rhoCu = 0.0175; // Ω·mm²/m, koper bij 20 °C
const standardSections = [1.5, 2.5, 4.0, 6.0, 10.0, 16.0, 25.0, 35.0, 50.0, 70.0, 95.0, 120.0];

const riggingDisclaimer =
    'Indicatieve berekening. Controleer altijd met de fabrikantgegevens (WLL, '
    'belastingtabellen) en laat rigging uitvoeren en keuren door een bevoegd rigger.';

final List<Calculator> calculators = [
  // ================= VIDEO =================
  Calculator(
    id: 'ledwall',
    category: 'Video',
    title: 'LED-wall',
    subtitle: 'Resolutie, maat, pitch, gewicht en stroom',
    icon: Icons.grid_view,
    fields: const [
      NumField('cols', 'Panelen breed', def: 6, decimals: 0),
      NumField('rows', 'Panelen hoog', def: 3, decimals: 0),
      NumField('pw', 'Paneelbreedte', unit: 'mm', def: 500, decimals: 0),
      NumField('ph', 'Paneelhoogte', unit: 'mm', def: 500, decimals: 0),
      NumField('pxw', 'Pixels breed per paneel', unit: 'px', def: 192, decimals: 0),
      NumField('pxh', 'Pixels hoog per paneel', unit: 'px', def: 192, decimals: 0),
      NumField('kg', 'Gewicht per paneel', unit: 'kg', def: 7.5, decimals: 1),
      NumField('watt', 'Max. vermogen per paneel', unit: 'W', def: 180, decimals: 0),
      NumField('pf', 'Arbeidsfactor (cos φ)', def: 0.95),
    ],
    compute: (i) {
      final o = CalcOutput();
      final cols = i.n('cols').round(), rows = i.n('rows').round();
      final pxw = i.n('pxw').round(), pxh = i.n('pxh').round();
      final pf = i.n('pf');
      if (cols < 1 || rows < 1 || pxw < 1 || pxh < 1 || i.n('pw') <= 0 || i.n('ph') <= 0) {
        return o.fail('Aantallen en maten moeten groter dan 0 zijn.');
      }
      if (pf <= 0 || pf > 1) return o.fail('cos φ ligt tussen 0 en 1.');
      final resW = cols * pxw, resH = rows * pxh;
      final w = cols * i.n('pw') / 1000, h = rows * i.n('ph') / 1000;
      final pitch = i.n('pw') / pxw;
      final gcd = _gcd(resW, resH);
      final n = cols * rows;
      final kg = n * i.n('kg');
      final watt = n * i.n('watt');
      final i1 = watt / (230 * pf);
      final i3 = watt / (sqrt(3) * 400 * pf);

      o.res('Resolutie', '$resW × $resH', unit: 'px', primary: true);
      o.res('Afmeting', '${f(w)} × ${f(h)}', unit: 'm', primary: true);
      o.res('Beeldverhouding', '${resW ~/ gcd}:${resH ~/ gcd} (${f(resW / resH)}:1)');
      o.res('Pixel pitch', f(pitch, 2), unit: 'mm');
      o.res('Min. kijkafstand (vuistregel)', f(pitch, 1), unit: 'm');
      o.res('Comfortabele kijkafstand', f(pitch * 3, 1), unit: 'm');
      o.res('Aantal panelen', '$n');
      o.res('Totaal gewicht', f(kg, 0), unit: 'kg');
      o.res('Max. vermogen', f(watt / 1000, 2), unit: 'kW');
      o.res('Stroom 1-fase 230 V', f(i1, 1), unit: 'A');
      o.res('Stroom per fase 3×400 V', f(i3, 1), unit: 'A');

      o.step('Resolutie = panelen × pixels per paneel');
      o.step('  breed: $cols × $pxw = $resW px');
      o.step('  hoog:  $rows × $pxh = $resH px');
      o.step('Afmeting = panelen × paneelmaat');
      o.step('  breed: $cols × ${f(i.n('pw'), 0)} mm = ${f(w)} m');
      o.step('  hoog:  $rows × ${f(i.n('ph'), 0)} mm = ${f(h)} m');
      o.step('Beeldverhouding: $resW : $resH, gedeeld door ggd $gcd = ${resW ~/ gcd}:${resH ~/ gcd}');
      o.step('Pixel pitch = paneelbreedte / pixels = ${f(i.n('pw'), 0)} / $pxw = ${f(pitch)} mm');
      o.step('Kijkafstand (vuistregel): minimaal ≈ pitch in mm → meters = ${f(pitch, 1)} m; comfortabel ≈ 3 × = ${f(pitch * 3, 1)} m');
      o.step('Gewicht = $n × ${f(i.n('kg'), 1)} kg = ${f(kg, 0)} kg (excl. frames/rigging)');
      o.step('Vermogen = $n × ${f(i.n('watt'), 0)} W = ${f(watt, 0)} W');
      o.step('1-fase: I = P / (U × cos φ) = ${f(watt, 0)} / (230 × ${f(pf)}) = ${f(i1, 1)} A');
      o.step('3-fase: I = P / (√3 × U × cos φ) = ${f(watt, 0)} / (1,732 × 400 × ${f(pf)}) = ${f(i3, 1)} A per fase');
      if (i1 > 16) {
        o.warn('Meer dan 16 A op 1-fase: verdeel over meerdere groepen of gebruik 3-fase.');
      }
      return o;
    },
  ),
  Calculator(
    id: 'scale',
    category: 'Video',
    title: 'Beeld schalen',
    subtitle: 'Bron in doel passen, balken en schaal',
    icon: Icons.aspect_ratio,
    fields: const [
      NumField('sw', 'Bron breed', unit: 'px', def: 1920, decimals: 0),
      NumField('sh', 'Bron hoog', unit: 'px', def: 1080, decimals: 0),
      NumField('tw', 'Doel breed', unit: 'px', def: 1152, decimals: 0),
      NumField('th', 'Doel hoog', unit: 'px', def: 576, decimals: 0),
      ChoiceField('mode', 'Schalen',
          options: [('fit', 'Passend (balken)'), ('fill', 'Vullend (bijsnijden)')],
          def: 'fit'),
    ],
    compute: (i) {
      final o = CalcOutput();
      final sw = i.n('sw'), sh = i.n('sh'), tw = i.n('tw'), th = i.n('th');
      if (sw <= 0 || sh <= 0 || tw <= 0 || th <= 0) {
        return o.fail('Alle resoluties moeten groter dan 0 zijn.');
      }
      final fx = tw / sw, fy = th / sh;
      final fit = i.c('mode') == 'fit';
      final s = fit ? min(fx, fy) : max(fx, fy);
      final w = sw * s, h = sh * s;
      o.res('Schaalfactor', '${f(s * 100, 1)} %', primary: true);
      o.res('Beeld na schalen', '${w.round()} × ${h.round()}', unit: 'px', primary: true);
      if (fit) {
        o.res('Balken links/rechts', f((tw - w) / 2, 0), unit: 'px');
        o.res('Balken boven/onder', f((th - h) / 2, 0), unit: 'px');
      } else {
        o.res('Bijgesneden links/rechts', f((w - tw) / 2, 0), unit: 'px');
        o.res('Bijgesneden boven/onder', f((h - th) / 2, 0), unit: 'px');
      }
      o.res('Verhouding bron', '${f(sw / sh)}:1');
      o.res('Verhouding doel', '${f(tw / th)}:1');
      o.step('Schaal horizontaal = ${f(tw, 0)} / ${f(sw, 0)} = ${f(fx, 4)}');
      o.step('Schaal verticaal   = ${f(th, 0)} / ${f(sh, 0)} = ${f(fy, 4)}');
      o.step(fit
          ? 'Passend: kleinste factor = ${f(s, 4)} (alles blijft zichtbaar)'
          : 'Vullend: grootste factor = ${f(s, 4)} (doel helemaal gevuld)');
      o.step('Nieuw formaat = ${f(sw, 0)} × ${f(s, 4)} en ${f(sh, 0)} × ${f(s, 4)} = ${f(w, 0)} × ${f(h, 0)} px');
      o.step(fit
          ? 'Balken = (doel − beeld) / 2 per zijde'
          : 'Bijsnijden = (beeld − doel) / 2 per zijde');
      return o;
    },
  ),
  Calculator(
    id: 'projection',
    category: 'Video',
    title: 'Projectie',
    subtitle: 'Worpafstand en beeldbreedte',
    icon: Icons.videocam_outlined,
    fields: [
      const ChoiceField('mode', 'Bereken',
          options: [('dist', 'Afstand'), ('width', 'Beeldbreedte')], def: 'dist'),
      const NumField('ratio', 'Throw ratio (lens)', def: 1.5),
      NumField('width', 'Beeldbreedte', unit: 'm', def: 4, visibleIf: (c) => c['mode'] == 'dist'),
      NumField('dist', 'Worpafstand', unit: 'm', def: 6, visibleIf: (c) => c['mode'] == 'width'),
      const ChoiceField('aspect', 'Beeldverhouding',
          options: [('16:9', '16:9'), ('16:10', '16:10'), ('4:3', '4:3')], def: '16:9'),
    ],
    compute: (i) {
      final o = CalcOutput();
      final r = i.n('ratio');
      if (r <= 0) return o.fail('De throw ratio moet groter dan 0 zijn.');
      final parts = i.c('aspect').split(':').map(double.parse).toList();
      final double width, dist;
      if (i.c('mode') == 'dist') {
        width = i.n('width');
        if (width <= 0) return o.fail('Beeldbreedte moet groter dan 0 zijn.');
        dist = width * r;
        o.res('Worpafstand', f(dist), unit: 'm', primary: true);
        o.step('Worpafstand = throw ratio × beeldbreedte = ${f(r)} × ${f(width)} = ${f(dist)} m');
      } else {
        dist = i.n('dist');
        if (dist <= 0) return o.fail('Worpafstand moet groter dan 0 zijn.');
        width = dist / r;
        o.res('Beeldbreedte', f(width), unit: 'm', primary: true);
        o.step('Beeldbreedte = worpafstand / throw ratio = ${f(dist)} / ${f(r)} = ${f(width)} m');
      }
      final height = width * parts[1] / parts[0];
      final diag = sqrt(width * width + height * height);
      o.res('Beeldhoogte', f(height), unit: 'm');
      o.res('Diagonaal', '${f(diag)} m (${f(diag / 0.0254, 0)}")');
      o.step('Hoogte = breedte × ${f(parts[1], 0)} / ${f(parts[0], 0)} = ${f(height)} m');
      o.step('Diagonaal = √(b² + h²) = ${f(diag)} m = ${f(diag / 0.0254, 0)} inch');
      o.step('De afstand is gemeten vanaf de lens tot het doek. Controleer lens-shift en zoombereik in de specificaties.');
      return o;
    },
  ),
  Calculator(
    id: 'bitrate',
    category: 'Video',
    title: 'Opname en bitrate',
    subtitle: 'Opslag per opnameduur',
    icon: Icons.sd_card_outlined,
    fields: const [
      NumField('mbps', 'Bitrate', unit: 'Mbit/s', def: 50, decimals: 1),
      NumField('min', 'Opnameduur', unit: 'min', def: 90, decimals: 0),
      NumField('disk', 'Beschikbare opslag', unit: 'GB', def: 256, decimals: 0),
    ],
    compute: (i) {
      final o = CalcOutput();
      final mbps = i.n('mbps'), mins = i.n('min'), disk = i.n('disk');
      if (mbps <= 0) return o.fail('Bitrate moet groter dan 0 zijn.');
      final gb = mbps * mins * 60 / 8 / 1000;
      final gbH = mbps * 3600 / 8 / 1000;
      final fitMin = disk * 1000 * 8 / mbps / 60;
      o.res('Benodigde opslag', f(gb, 1), unit: 'GB', primary: true);
      o.res('Per uur', f(gbH, 1), unit: 'GB');
      o.res('Past op ${f(disk, 0)} GB', '${f(fitMin, 0)} min (${duration(Duration(minutes: fitMin.floor()))})');
      o.step('Megabit → megabyte: delen door 8');
      o.step('Opslag = ${f(mbps, 1)} Mbit/s × ${f(mins * 60, 0)} s / 8 / 1000 = ${f(gb, 2)} GB');
      o.step('Per uur = ${f(mbps, 1)} × 3600 / 8 / 1000 = ${f(gbH, 2)} GB');
      o.step('Duur = ${f(disk, 0)} GB × 1000 × 8 / ${f(mbps, 1)} / 60 = ${f(fitMin, 0)} min');
      o.step('Uitgegaan van 1 GB = 1000 MB (zoals op kaarten en schijven). Houd ~10 % marge aan.');
      if (gb > disk) o.warn('De opname past niet op de opgegeven opslag.', severe: true);
      return o;
    },
  ),

  // ================= RIGGING =================
  Calculator(
    id: 'bridle',
    category: 'Rigging',
    title: 'Bridle',
    subtitle: 'Pootlengtes en krachten, op diepte of hoek',
    icon: Icons.change_history,
    disclaimer: riggingDisclaimer,
    fields: [
      const ChoiceField('mode', 'Uitgaan van',
          options: [('angle', 'Gewenste hoek'), ('depth', 'Apex-diepte')], def: 'angle'),
      const NumField('d', 'Afstand tussen punten A–B', unit: 'm', def: 4),
      const NumField('dh', 'Hoogteverschil B t.o.v. A', unit: 'm', def: 0),
      const NumField('x', 'Apex horizontaal vanaf A', unit: 'm', def: 2),
      NumField('angle', 'Gewenste hoek tussen poten', unit: '°', def: 90, decimals: 1,
          visibleIf: (c) => c['mode'] == 'angle'),
      NumField('h', 'Apex onder punt A', unit: 'm', def: 2,
          visibleIf: (c) => c['mode'] == 'depth'),
      const NumField('w', 'Last', unit: 'kg', def: 500, decimals: 0),
    ],
    diagram: (i, o) => BridleDiagram(o.extra),
    compute: (i) {
      final o = CalcOutput();
      final d = i.n('d'), dh = i.n('dh'), x = i.n('x'), w = i.n('w');
      if (d <= 0) return o.fail('Afstand tussen de punten moet groter dan 0 zijn.');
      if (x <= 0 || x >= d) {
        return o.fail('De apex moet tussen de punten liggen (0 < x < ${f(d)} m).');
      }
      if (w <= 0) return o.fail('De last moet groter dan 0 zijn.');

      o.step('Assenstelsel: punt A = (0; 0), punt B = (${f(d)}; ${f(dh)}) m');
      double h;
      if (i.c('mode') == 'angle') {
        final a = i.n('angle');
        if (a <= 0 || a >= 180) return o.fail('De hoek ligt tussen 0° en 180°.');
        h = bridleDepthForAngle(d: d, dh: dh, x: x, angleDeg: a);
        o.step('Gevraagd: hoek tussen de poten = ${f(a, 1)}°');
        if (dh.abs() < 1e-9 && (x - d / 2).abs() < 1e-9) {
          final hc = (d / 2) / tan(a / 2 * pi / 180);
          o.step('Symmetrisch (gelijke hoogte, apex in het midden):');
          o.step('  h = (D/2) / tan(θ/2) = ${f(d / 2)} / tan(${f(a / 2, 1)}°) = ${f(hc, 3)} m');
        } else {
          o.step('Niet-symmetrisch: h numeriek gezocht (bisectie) tot de hoek klopt');
          o.step('  → h = ${f(h, 3)} m onder A');
        }
      } else {
        h = i.n('h');
        if (h <= 0 || h + dh <= 0) {
          return o.fail('De apex moet onder beide punten hangen.');
        }
      }
      final r = bridle(d: d, dh: dh, x: x, h: h, w: w);
      final hb = h + dh;
      o.extra.addAll({'d': d, 'dh': dh, 'x': x, 'h': h, 'angle': r.angle});

      o.res('Kracht poot A', f(r.ta, 0), unit: 'kg', primary: true);
      o.res('Kracht poot B', f(r.tb, 0), unit: 'kg', primary: true);
      o.res('Lengte poot A', f(r.la), unit: 'm', primary: true);
      o.res('Lengte poot B', f(r.lb), unit: 'm', primary: true);
      o.res('Hoek tussen poten', f(r.angle, 1), unit: '°');
      o.res('Apex onder A', f(h), unit: 'm');
      o.res('Poothoeken t.o.v. verticaal', 'A ${f(r.angleA, 1)}° · B ${f(r.angleB, 1)}°');
      o.res('Horizontale kracht op de punten', f(r.horizontal, 0), unit: 'kg');
      o.res('In kN', 'A ${f(r.ta * g / 1000)} · B ${f(r.tb * g / 1000)}', unit: 'kN');

      o.step('Apex P = (x; −h) = (${f(x)}; −${f(h, 3)}) m');
      o.step('Lengte poot A: La = √(x² + h²) = √(${f(x)}² + ${f(h, 3)}²) = ${f(r.la, 3)} m');
      o.step('Lengte poot B: Lb = √((D−x)² + (h+dh)²) = √(${f(d - x)}² + ${f(hb, 3)}²) = ${f(r.lb, 3)} m');
      o.step('Hoek tussen poten: θ = acos(uA · uB) = ${f(r.angle, 1)}°');
      o.step('Evenwicht in de apex:');
      o.step('  horizontaal: TA·x/La = TB·(D−x)/Lb');
      o.step('  verticaal:   TA·h/La + TB·(h+dh)/Lb = W');
      final denom = x * hb + (d - x) * h;
      o.step('Noemer N = x·(h+dh) + (D−x)·h = ${f(x)}·${f(hb, 3)} + ${f(d - x)}·${f(h, 3)} = ${f(denom, 3)}');
      o.step('TA = W·(D−x)·La / N = ${f(w, 0)}·${f(d - x)}·${f(r.la, 3)} / ${f(denom, 3)} = ${f(r.ta, 1)} kg');
      o.step('TB = W·x·Lb / N = ${f(w, 0)}·${f(x)}·${f(r.lb, 3)} / ${f(denom, 3)} = ${f(r.tb, 1)} kg');
      o.step('Horizontaal = TA·x/La = ${f(r.horizontal, 1)} kg');
      o.step('kN = kg × 9,81 / 1000');
      o.step('Pootlengtes zijn hart-op-hart van ankerpunt tot apex; reken shackles, steels en rondsling zelf mee.');

      if (r.angle > 120) {
        o.warn('Hoek groter dan 120°: elke poot krijgt meer dan de volle last. Niet toepassen.', severe: true);
      } else if (r.angle > 90) {
        o.warn('Hoek groter dan 90°: de krachten lopen snel op. Richtlijn is maximaal 90° tot 120°.');
      }
      return o;
    },
  ),
  Calculator(
    id: 'truss',
    category: 'Rigging',
    title: 'Truss: puntlast',
    subtitle: 'Verdeling over twee ophangpunten',
    icon: Icons.linear_scale,
    disclaimer: riggingDisclaimer,
    fields: const [
      NumField('l', 'Overspanning tussen punten', unit: 'm', def: 8),
      NumField('p', 'Puntlast', unit: 'kg', def: 150, decimals: 0),
      NumField('a', 'Positie last vanaf punt A', unit: 'm', def: 3),
      NumField('q', 'Eigen gewicht truss', unit: 'kg/m', def: 7, decimals: 1),
    ],
    compute: (i) {
      final o = CalcOutput();
      final l = i.n('l'), p = i.n('p'), a = i.n('a'), q = i.n('q');
      if (l <= 0) return o.fail('De overspanning moet groter dan 0 zijn.');
      if (a < 0 || a > l) return o.fail('De last moet tussen de punten hangen (0 tot ${f(l)} m).');
      final ra = p * (l - a) / l + q * l / 2;
      final rb = p * a / l + q * l / 2;
      final m = p * a * (l - a) / l + q * l * l / 8; // kgm (bij benadering, maxima opgeteld)
      o.res('Punt A', f(ra, 0), unit: 'kg', primary: true);
      o.res('Punt B', f(rb, 0), unit: 'kg', primary: true);
      o.res('Totaal', f(ra + rb, 0), unit: 'kg');
      o.res('Max. buigend moment (≈)', f(m * g / 1000), unit: 'kNm');
      o.step('Puntlast verdeelt naar rato van de afstand tot het andere punt:');
      o.step('  A = P·(L−a)/L = ${f(p, 0)}·${f(l - a)}/${f(l)} = ${f(p * (l - a) / l, 1)} kg');
      o.step('  B = P·a/L = ${f(p, 0)}·${f(a)}/${f(l)} = ${f(p * a / l, 1)} kg');
      o.step('Eigen gewicht truss: q·L/2 per punt = ${f(q, 1)}·${f(l)}/2 = ${f(q * l / 2, 1)} kg');
      o.step('Moment puntlast = P·a·(L−a)/L; moment eigen gewicht = q·L²/8');
      o.step('  (beide maxima opgeteld: veilige bovengrens) = ${f(m, 0)} kgm = ${f(m * g / 1000)} kNm');
      o.step('Vergelijk het moment en de puntlast met de belastingtabel van de truss.');
      return o;
    },
  ),

  // ================= STROOM =================
  Calculator(
    id: 'power',
    category: 'Stroom',
    title: 'Vermogen ↔ stroom',
    subtitle: '1-fase en 3-fase',
    icon: Icons.bolt,
    fields: [
      const ChoiceField('mode', 'Bereken',
          options: [('i', 'Stroom uit vermogen'), ('p', 'Vermogen uit stroom')], def: 'i'),
      const ChoiceField('sys', 'Net',
          options: [('1', '1-fase 230 V'), ('3', '3-fase 400 V')], def: '1'),
      NumField('kw', 'Vermogen', unit: 'kW', def: 3, visibleIf: (c) => c['mode'] == 'i'),
      NumField('a', 'Stroom (per fase)', unit: 'A', def: 16, decimals: 1,
          visibleIf: (c) => c['mode'] == 'p'),
      const NumField('pf', 'Arbeidsfactor (cos φ)', def: 1),
    ],
    compute: (i) {
      final o = CalcOutput();
      final pf = i.n('pf');
      if (pf <= 0 || pf > 1) return o.fail('cos φ ligt tussen 0 en 1.');
      final three = i.c('sys') == '3';
      final u = three ? 400.0 : 230.0;
      final k = three ? sqrt(3) : 1.0;
      final form = three ? '√3 × U × cos φ' : 'U × cos φ';
      if (i.c('mode') == 'i') {
        final p = i.n('kw') * 1000;
        final a = p / (k * u * pf);
        o.res(three ? 'Stroom per fase' : 'Stroom', f(a, 1), unit: 'A', primary: true);
        o.step('I = P / ($form)');
        o.step('  = ${f(p, 0)} / (${three ? '1,732 × ' : ''}${f(u, 0)} × ${f(pf)}) = ${f(a, 2)} A');
        if (!three && a > 16) o.warn('Meer dan 16 A: past niet op een standaard Schuko-groep.');
      } else {
        final a = i.n('a');
        final p = k * u * pf * a;
        o.res('Vermogen', f(p / 1000), unit: 'kW', primary: true);
        o.step('P = $form × I');
        o.step('  = ${three ? '1,732 × ' : ''}${f(u, 0)} × ${f(pf)} × ${f(a, 1)} = ${f(p, 0)} W');
      }
      o.step(three
          ? 'Bij 3-fase met gelijk verdeelde belasting.'
          : 'cos φ = 1 voor ohmse last; LED-voedingen met PFC ≈ 0,95.');
      return o;
    },
  ),
  Calculator(
    id: 'kva',
    category: 'Stroom',
    title: 'kW ↔ kVA',
    subtitle: 'Werkelijk en schijnbaar vermogen, aggregaat',
    icon: Icons.electrical_services,
    fields: [
      const ChoiceField('mode', 'Bereken',
          options: [('kva', 'kVA uit kW'), ('kw', 'kW uit kVA')], def: 'kva'),
      NumField('kw', 'Werkelijk vermogen', unit: 'kW', def: 40,
          visibleIf: (c) => c['mode'] == 'kva'),
      NumField('kva', 'Schijnbaar vermogen', unit: 'kVA', def: 100,
          visibleIf: (c) => c['mode'] == 'kw'),
      const NumField('pf', 'Arbeidsfactor (cos φ)', def: 0.8),
      const ChoiceField('sys', 'Net',
          options: [('3', '3-fase 400 V'), ('1', '1-fase 230 V')], def: '3'),
    ],
    compute: (i) {
      final o = CalcOutput();
      final pf = i.n('pf');
      if (pf <= 0 || pf > 1) return o.fail('cos φ ligt tussen 0 en 1.');
      final double kw, kva;
      if (i.c('mode') == 'kva') {
        kw = i.n('kw');
        kva = kw / pf;
        o.res('Schijnbaar vermogen', f(kva, 1), unit: 'kVA', primary: true);
        o.step('S = P / cos φ = ${f(kw, 1)} / ${f(pf)} = ${f(kva, 2)} kVA');
      } else {
        kva = i.n('kva');
        kw = kva * pf;
        o.res('Werkelijk vermogen', f(kw, 1), unit: 'kW', primary: true);
        o.step('P = S × cos φ = ${f(kva, 1)} × ${f(pf)} = ${f(kw, 2)} kW');
      }
      if (kw < 0) return o.fail('Vermogen kan niet negatief zijn.');
      final kvar = sqrt(max(0, kva * kva - kw * kw));
      o.res('Blindvermogen', f(kvar, 1), unit: 'kvar');
      o.step('Q = √(S² − P²) = √(${f(kva, 1)}² − ${f(kw, 1)}²) = ${f(kvar, 2)} kvar');
      final three = i.c('sys') == '3';
      final a = three ? kva * 1000 / (sqrt(3) * 400) : kva * 1000 / 230;
      o.res(three ? 'Stroom per fase' : 'Stroom', f(a, 1), unit: 'A');
      o.step(three
          ? 'I = S / (√3 × 400 V) = ${f(kva * 1000, 0)} / 692,8 = ${f(a, 1)} A'
          : 'I = S / 230 V = ${f(kva * 1000, 0)} / 230 = ${f(a, 1)} A');
      o.step('Aggregaten worden in kVA opgegeven, meestal bij cos φ 0,8. '
          'Kies een aggregaat met marge (ca. 20–25 %) boven je berekende kVA.');
      if (three && a > 63 && a <= 125) o.warn('Meer dan 63 A per fase: 125A-CEE of Powerlock nodig.');
      if (three && a > 125) o.warn('Meer dan 125 A per fase: Powerlock nodig.');
      return o;
    },
  ),
  Calculator(
    id: 'vdrop',
    category: 'Stroom',
    title: 'Spanningsval en kabel',
    subtitle: 'Val over de kabel en min. doorsnede',
    icon: Icons.cable,
    fields: const [
      ChoiceField('sys', 'Net', options: [('1', '1-fase 230 V'), ('3', '3-fase 400 V')], def: '1'),
      NumField('l', 'Kabellengte (enkel)', unit: 'm', def: 50, decimals: 0),
      NumField('a', 'Stroom', unit: 'A', def: 16, decimals: 1),
      NumField('s', 'Doorsnede', unit: 'mm²', def: 2.5, decimals: 1),
      NumField('pf', 'Arbeidsfactor (cos φ)', def: 1),
      NumField('max', 'Max. toegestane val', unit: '%', def: 5, decimals: 1),
    ],
    compute: (i) {
      final o = CalcOutput();
      final l = i.n('l'), a = i.n('a'), s = i.n('s'), pf = i.n('pf'), mx = i.n('max');
      if (s <= 0 || l <= 0) return o.fail('Lengte en doorsnede moeten groter dan 0 zijn.');
      if (pf <= 0 || pf > 1) return o.fail('cos φ ligt tussen 0 en 1.');
      if (mx <= 0) return o.fail('Max. val moet groter dan 0 zijn.');
      final three = i.c('sys') == '3';
      final u = three ? 400.0 : 230.0;
      final k = three ? sqrt(3) : 2.0;
      final du = k * l * a * rhoCu * pf / s;
      final pct = du / u * 100;
      final sMin = k * l * a * rhoCu * pf / (mx / 100 * u);
      final std = standardSections.firstWhere((x) => x >= sMin, orElse: () => double.nan);
      o.res('Spanningsval', f(du, 1), unit: 'V', primary: true);
      o.res('Spanningsval', f(pct, 1), unit: '%', primary: true);
      o.res('Spanning aan het eind', f(u - du, 0), unit: 'V');
      o.res('Min. doorsnede voor ${f(mx, 1)} %', f(sMin, 2), unit: 'mm²');
      o.res('Eerstvolgende standaardmaat', std.isNaN ? '> 120' : f(std, 1), unit: 'mm²');
      o.step('ρ koper = 0,0175 Ω·mm²/m (bij 20 °C)');
      o.step(three
          ? 'ΔU = √3 × L × I × ρ × cos φ / A'
          : 'ΔU = 2 × L × I × ρ × cos φ / A   (heen en terug)');
      o.step('   = ${three ? '1,732' : '2'} × ${f(l, 0)} × ${f(a, 1)} × 0,0175 × ${f(pf)} / ${f(s, 1)} = ${f(du, 2)} V');
      o.step('ΔU % = ${f(du, 2)} / ${f(u, 0)} × 100 = ${f(pct, 2)} %');
      o.step('A min = ${three ? '1,732' : '2'} × L × I × ρ × cos φ / (${f(mx, 1)} % × ${f(u, 0)} V) = ${f(sMin, 2)} mm²');
      o.step('Let op: dit is alleen de spanningsval. Controleer ook de stroombelastbaarheid van de kabel en de beveiliging.');
      if (pct > mx) {
        o.warn('Spanningsval boven ${f(mx, 1)} %: kies een dikkere kabel of kortere lengte.', severe: true);
      }
      return o;
    },
  ),

  // ================= GELUID =================
  Calculator(
    id: 'delay',
    category: 'Geluid',
    title: 'Delay',
    subtitle: 'Vertraging per afstand',
    icon: Icons.timer_outlined,
    fields: const [
      NumField('d', 'Afstand', unit: 'm', def: 20, decimals: 1),
      NumField('t', 'Temperatuur', unit: '°C', def: 20, decimals: 0),
    ],
    compute: (i) {
      final o = CalcOutput();
      final d = i.n('d'), t = i.n('t');
      final c = 331.3 + 0.606 * t;
      final ms = d / c * 1000;
      o.res('Delay', f(ms, 2), unit: 'ms', primary: true);
      o.res('Geluidssnelheid', f(c, 1), unit: 'm/s');
      o.res('Samples bij 48 kHz', f(ms * 48, 0));
      o.res('Samples bij 96 kHz', f(ms * 96, 0));
      o.step('c = 331,3 + 0,606 × T = 331,3 + 0,606 × ${f(t, 0)} = ${f(c, 2)} m/s');
      o.step('t = afstand / c = ${f(d, 1)} / ${f(c, 2)} = ${f(ms / 1000, 5)} s = ${f(ms, 2)} ms');
      o.step('Samples = ms × samplefrequentie in kHz');
      return o;
    },
  ),
  Calculator(
    id: 'db',
    category: 'Geluid',
    title: 'dB optellen en afstand',
    subtitle: 'Bronnen optellen, kwadratenwet',
    icon: Icons.graphic_eq,
    fields: const [
      NumField('l1', 'Niveau bron 1', unit: 'dB', def: 100, decimals: 1),
      NumField('l2', 'Niveau bron 2', unit: 'dB', def: 100, decimals: 1),
      NumField('d1', 'Gemeten op afstand', unit: 'm', def: 1, decimals: 1),
      NumField('d2', 'Nieuwe afstand', unit: 'm', def: 10, decimals: 1),
    ],
    compute: (i) {
      final o = CalcOutput();
      final l1 = i.n('l1'), l2 = i.n('l2'), d1 = i.n('d1'), d2 = i.n('d2');
      if (d1 <= 0 || d2 <= 0) return o.fail('Afstanden moeten groter dan 0 zijn.');
      final sum = 10 * log(pow(10, l1 / 10) + pow(10, l2 / 10)) / ln10;
      final atD2 = sum - 20 * log(d2 / d1) / ln10;
      o.res('Som bron 1 + 2', f(sum, 1), unit: 'dB', primary: true);
      o.res('Som op ${f(d2, 1)} m', f(atD2, 1), unit: 'dB', primary: true);
      o.step('L = 10 × log10(10^(L1/10) + 10^(L2/10))');
      o.step('  = 10 × log10(10^${f(l1 / 10, 2)} + 10^${f(l2 / 10, 2)}) = ${f(sum, 2)} dB');
      o.step('Twee gelijke bronnen: +3 dB (incoherent).');
      o.step('Kwadratenwet (puntbron, vrij veld): L2 = L1 − 20 × log10(d2/d1)');
      o.step('  = ${f(sum, 2)} − 20 × log10(${f(d2, 1)}/${f(d1, 1)}) = ${f(atD2, 2)} dB');
      o.step('Line arrays verliezen in het nabije veld ongeveer 3 dB per afstandsverdubbeling in plaats van 6 dB.');
      return o;
    },
  ),

  // ================= LICHT =================
  Calculator(
    id: 'dmx',
    category: 'Licht',
    title: 'DMX-adressen',
    subtitle: 'Adressen per armatuur en universe',
    icon: Icons.lightbulb_outline,
    fields: const [
      NumField('start', 'Startadres', def: 1, decimals: 0),
      NumField('ch', 'Kanalen per armatuur', def: 16, decimals: 0),
      NumField('n', 'Aantal armaturen', def: 12, decimals: 0),
      NumField('u', 'Start-universe', def: 1, decimals: 0),
    ],
    compute: (i) {
      final o = CalcOutput();
      final start = i.n('start').round(), ch = i.n('ch').round();
      final n = i.n('n').round();
      var u = i.n('u').round();
      if (start < 1 || start > 512) return o.fail('Startadres ligt tussen 1 en 512.');
      if (ch < 1 || ch > 512) return o.fail('Kanalen per armatuur tussen 1 en 512.');
      if (n < 1 || n > 512) return o.fail('Aantal armaturen tussen 1 en 512.');
      o.step('Volgend adres = vorig adres + $ch kanalen');
      o.step('Past een armatuur niet meer voor kanaal 512 (adres + $ch − 1 > 512), dan begint hij op adres 1 van de volgende universe.');
      var addr = start;
      var jumps = 0;
      for (var k = 1; k <= n; k++) {
        if (addr + ch - 1 > 512) {
          u++;
          addr = 1;
          jumps++;
        }
        o.res('Armatuur $k', 'U$u · $addr–${addr + ch - 1}', primary: k == 1);
        addr += ch;
      }
      final perUniverse = 512 ~/ ch;
      o.step('Per universe passen 512 / $ch = $perUniverse armaturen (afgerond naar beneden).');
      if (jumps > 0) o.warn('De patch loopt over $jumps universe-grens(en).');
      return o;
    },
  ),
  Calculator(
    id: 'dip',
    category: 'Licht',
    title: 'DIP-switch',
    subtitle: 'DMX-adres naar schakelaars',
    icon: Icons.toggle_on_outlined,
    fields: const [NumField('a', 'DMX-adres', def: 101, decimals: 0)],
    compute: (i) {
      final o = CalcOutput();
      final a = i.n('a').round();
      if (a < 1 || a > 511) return o.fail('Adres ligt tussen 1 en 511 (9 schakelaars).');
      final on = <int>[];
      final parts = <String>[];
      for (var b = 0; b < 9; b++) {
        if (a & (1 << b) != 0) {
          on.add(b + 1);
          parts.add('${1 << b}');
        }
      }
      final visual = List.generate(9, (b) => a & (1 << b) != 0 ? '▮' : '▯').join(' ');
      o.res('Schakelaars AAN', on.join(', '), primary: true);
      o.res('1 2 3 4 5 6 7 8 9', visual);
      o.step('Elke schakelaar heeft een waarde: 1=1, 2=2, 3=4, 4=8, 5=16, 6=32, 7=64, 8=128, 9=256');
      o.step('$a binair = ${a.toRadixString(2).padLeft(9, '0')} (rechts = schakelaar 1)');
      o.step('$a = ${parts.join(' + ')}');
      o.step('Sommige armaturen tellen vanaf 0 of hebben schakelaar 10 voor een functie: check de handleiding.');
      return o;
    },
  ),
];

const categoryOrder = ['Video', 'Rigging', 'Stroom', 'Geluid', 'Licht'];
