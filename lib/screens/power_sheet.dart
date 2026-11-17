import 'package:flutter/material.dart';

import 'common.dart';

/// Spiekbrief stroom: aansluitingen, kabels, kleuren en vuistregels.
/// Volledig offline.
class PowerSheetScreen extends StatelessWidget {
  const PowerSheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Spiekbrief stroom')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              const SectionTitle('Aansluitingen'),
              _table(context, const ['Aansluiting', 'Net', 'Max. vermogen'], const [
                ['Schuko (randaarde)', '230 V · 16 A', '3,7 kW'],
                ['CEE 16 A blauw (3-polig)', '230 V · 16 A', '3,7 kW'],
                ['CEE 32 A blauw (3-polig)', '230 V · 32 A', '7,4 kW'],
                ['CEE 16 A rood (5-polig)', '3 × 400 V · 16 A', '11 kW'],
                ['CEE 32 A rood', '3 × 400 V · 32 A', '22 kW'],
                ['CEE 63 A rood', '3 × 400 V · 63 A', '44 kW'],
                ['CEE 125 A rood', '3 × 400 V · 125 A', '87 kW'],
                ['Powerlock 400 A', '3 × 400 V · 400 A', '277 kVA'],
              ]),
              const _Note('Bij cos φ = 1. 3-fase: P = √3 × 400 V × I. '
                  'CEE-kleur: geel 110 V, blauw 230 V, rood 400 V.'),
              const SectionTitle('Kabel (H07RN-F) en stroom'),
              _table(context, const ['Doorsnede', 'Gangbaar voor', 'Let op'], const [
                ['1,5 mm²', '16 A', 'korte lengtes'],
                ['2,5 mm²', '16 A', 'langere Schuko/CEE16-lijnen'],
                ['4 mm²', '32 A', ''],
                ['6 mm²', '32 A', 'lange 32A-lijnen'],
                ['10 mm²', '63 A', ''],
                ['16 mm²', '63 A', 'lange 63A-lijnen'],
                ['25 mm²', '125 A', 'korte lengtes'],
                ['35 mm²', '125 A', ''],
                ['95–120 mm² (enkeladerig)', '400 A', 'Powerlock'],
              ]),
              const _Note('Indicatief. Belastbaarheid hangt af van lengte, '
                  'opgerold of los, temperatuur en bundeling. Rol kabelhaspels '
                  'volledig af. Controleer de spanningsval met de calculator.'),
              const SectionTitle('Aderkleuren'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 8, runSpacing: 8, children: const [
                    _Wire('L1', 'bruin', Color(0xFF8B5A2B)),
                    _Wire('L2', 'zwart', Color(0xFF000000)),
                    _Wire('L3', 'grijs', Color(0xFF9E9E9E)),
                    _Wire('N', 'blauw', Color(0xFF1E64C8)),
                    _Wire('PE', 'geel/groen', Color(0xFF7DB52F)),
                  ]),
                ),
              ),
              const SectionTitle('Vuistregels'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in const [
                        ('1 kW op 230 V', '≈ 4,3 A'),
                        ('1 kW op 3-fase 400 V', '≈ 1,44 A per fase'),
                        ('1 A op 230 V', '≈ 230 W'),
                        ('16 A Schuko-groep', 'max. ≈ 3.600 W'),
                        ('kVA → kW', 'kVA × cos φ (aggregaat: × 0,8)'),
                        ('100 kVA aggregaat', '≈ 80 kW, ≈ 144 A per fase'),
                        ('Spanningsval', 'max. 5 % (230 V: 11,5 V)'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Text(r.$1)),
                                const SizedBox(width: 8),
                                Text(r.$2,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        color: primary,
                                        fontWeight: FontWeight.w600)),
                              ]),
                        ),
                    ],
                  ),
                ),
              ),
              const SectionTitle('Praktijk'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final t in const [
                        'Verdeel de belasting gelijk over de drie fasen.',
                        'Veel schakelende voedingen (LED, video, laptops) geven '
                            'harmonischen: de nul kan zwaarder belast worden dan de fasen.',
                        'LED-walls en grote voedingen hebben een hoge inschakelstroom: '
                            'schakel per groep in, niet alles tegelijk.',
                        'Eindgroepen achter een aardlekschakelaar van 30 mA.',
                        'Licht, geluid en video bij voorkeur op aparte groepen '
                            '(minder brom en storing).',
                        'Meet bij een aggregaat of onbekende aansluiting eerst '
                            'spanning en draairichting.',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('•  ', style: TextStyle(color: primary)),
                                Expanded(child: Text(t)),
                              ]),
                        ),
                    ],
                  ),
                ),
              ),
              const _Note('Indicatief overzicht. Elektrische installaties '
                  'aanleggen en keuren volgens NEN 1010 / NEN 3140 door een '
                  'bevoegd persoon.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _table(BuildContext context, List<String> head, List<List<String>> rows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1.6),
            1: FlexColumnWidth(1.3),
            2: FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(children: [
              for (final h in head)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                  child: Text(h,
                      style: const TextStyle(
                          color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ]),
            for (final r in rows)
              TableRow(
                decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFF2A2B2F)))),
                children: [
                  for (var i = 0; i < r.length; i++)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      child: Text(r[i],
                          style: TextStyle(
                              fontSize: 13,
                              color: i == 2 && head[2] != 'Let op'
                                  ? Theme.of(context).colorScheme.primary
                                  : (i == 2 ? muted : null),
                              fontWeight: i == 2 && head[2] != 'Let op'
                                  ? FontWeight.w600
                                  : null)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(text, style: const TextStyle(color: muted, fontSize: 12)),
      );
}

class _Wire extends StatelessWidget {
  final String name;
  final String color;
  final Color swatch;
  const _Wire(this.name, this.color, this.swatch);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(
          color: const Color(0xFF232428),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: name == 'PE' ? null : swatch,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF555555)),
              gradient: name == 'PE'
                  ? const LinearGradient(colors: [
                      Color(0xFFE8D23A),
                      Color(0xFFE8D23A),
                      Color(0xFF3D9A3D),
                      Color(0xFF3D9A3D),
                    ], stops: [0, 0.5, 0.5, 1])
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text('$name  ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(color, style: const TextStyle(color: muted)),
        ]),
      );
}
