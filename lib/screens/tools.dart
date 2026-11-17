import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../calc/defs.dart';
import '../format.dart';
import '../store.dart';
import 'apps.dart';
import 'clock.dart';
import 'common.dart';
import 'docs.dart';
import 'power_sheet.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  Widget _addButton(BuildContext context, String section) => IconButton(
        tooltip: 'App of link toevoegen aan $section',
        icon: const Icon(Icons.add, size: 20),
        onPressed: () => addAppOrLink(context, section: section),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tools'), actions: [
        IconButton(
          tooltip: 'App of link toevoegen',
          icon: const Icon(Icons.add_to_home_screen),
          onPressed: () => addAppOrLink(context),
        ),
        const SettingsAction(),
      ]),
      body: StoreBuilder(builder: (context) {
        final general = visibleApps('Algemeen');
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text('Calculators werken volledig offline.',
                style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _BigTile(
                  icon: Icons.access_time,
                  label: 'Klok',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ClockScreen())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigTile(
                  icon: Icons.folder_open,
                  label: 'Documenten & links',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LibraryScreen())),
                ),
              ),
            ]),
            if (general.isNotEmpty) ...[
              SectionTitle('Apps en links',
                  trailing: _addButton(context, 'Algemeen')),
              TileGrid(children: [
                for (final a in general) AppTileCard(tile: a),
              ]),
            ],
            for (final cat in categoryOrder) ...[
              SectionTitle(cat, trailing: _addButton(context, cat)),
              TileGrid(children: [
                for (final c in calculators.where((c) => c.category == cat))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: Icon(c.icon,
                            color: Theme.of(context).colorScheme.primary),
                        title: Text(c.title),
                        subtitle: Text(c.subtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => CalcScreen(calc: c))),
                      ),
                    ),
                  ),
                if (cat == 'Stroom')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: Icon(Icons.menu_book_outlined,
                            color: Theme.of(context).colorScheme.primary),
                        title: const Text('Spiekbrief stroom'),
                        subtitle: const Text(
                            'Aansluitingen, kabels, kleuren, vuistregels'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const PowerSheetScreen())),
                      ),
                    ),
                  ),
                for (final a in visibleApps(cat)) AppTileCard(tile: a),
              ]),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => addAppOrLink(context),
              icon: const Icon(Icons.add),
              label: const Text('App of link toevoegen'),
            ),
          ],
        );
      }),
    );
  }
}

class _BigTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BigTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: Column(children: [
              Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

class CalcScreen extends StatefulWidget {
  final Calculator calc;
  const CalcScreen({super.key, required this.calc});

  @override
  State<CalcScreen> createState() => _CalcScreenState();
}

class _CalcScreenState extends State<CalcScreen> {
  final _ctrl = <String, TextEditingController>{};
  final _choices = <String, String>{};

  @override
  void initState() {
    super.initState();
    final saved = store.calcInputs(widget.calc.id);
    for (final f in widget.calc.fields) {
      if (f is NumField) {
        _ctrl[f.id] =
            TextEditingController(text: saved[f.id] ?? nf(f.def, f.decimals));
      } else if (f is ChoiceField) {
        final s = saved[f.id];
        _choices[f.id] =
            f.options.any((o) => o.$1 == s) ? s! : f.def;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    store.saveCalcInputs(widget.calc.id, {
      for (final e in _ctrl.entries) e.key: e.value.text,
      ..._choices,
    });
    setState(() {});
  }

  void _reset() {
    for (final f in widget.calc.fields) {
      if (f is NumField) _ctrl[f.id]!.text = nf(f.def, f.decimals);
      if (f is ChoiceField) _choices[f.id] = f.def;
    }
    _changed();
  }

  bool _visible(Field f) => f.visibleIf?.call(_choices) ?? true;

  CalcOutput _compute() {
    final nums = <String, double>{};
    for (final f in widget.calc.fields) {
      if (f is NumField) {
        final v = parseNum(_ctrl[f.id]!.text);
        if (v == null) {
          if (_visible(f)) {
            return CalcOutput().fail('Vul "${f.label}" in met een getal.');
          }
          nums[f.id] = f.def;
        } else {
          nums[f.id] = v;
        }
      }
    }
    try {
      return widget.calc.compute(Inputs(nums, Map.of(_choices)));
    } catch (e) {
      return CalcOutput().fail('Kan dit niet berekenen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.calc;
    final out = _compute();
    final scheme = Theme.of(context).colorScheme;
    final primary = out.results.where((r) => r.primary).toList();
    final other = out.results.where((r) => !r.primary).toList();

    return Scaffold(
      appBar: AppBar(title: Text(c.title), actions: [
        IconButton(
            tooltip: 'Standaardwaarden',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt)),
      ]),
      body: LayoutBuilder(builder: (context, box) {
        final inputs = <Widget>[
          // ---------- Invoer ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final f in c.fields.where(_visible))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: f is ChoiceField
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.label,
                                    style: const TextStyle(color: muted, fontSize: 12)),
                                const SizedBox(height: 6),
                                SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  segments: [
                                    for (final o in f.options)
                                      ButtonSegment(value: o.$1, label: Text(o.$2)),
                                  ],
                                  selected: {_choices[f.id]!},
                                  onSelectionChanged: (s) {
                                    _choices[f.id] = s.first;
                                    _changed();
                                  },
                                ),
                              ],
                            )
                          : TextField(
                              controller: _ctrl[f.id],
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true, signed: true),
                              decoration: InputDecoration(
                                labelText: f.label,
                                suffixText: (f as NumField).unit,
                                isDense: true,
                              ),
                              onChanged: (_) => _changed(),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ];
        final results = <Widget>[
          // ---------- Uitkomst ----------
          if (out.error != null)
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(out.error!,
                    style: TextStyle(color: scheme.onErrorContainer)),
              ),
            )
          else ...[
            if (c.diagram != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: c.diagram!(Inputs(const {}, _choices), out),
                ),
              ),
            if (c.diagram != null) const SizedBox(height: 8),
            if (primary.isNotEmpty)
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.1,
                children: [
                  for (final r in primary)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(r.label,
                                style: const TextStyle(color: muted, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                  '${r.value}${r.unit.isEmpty ? '' : ' ${r.unit}'}',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.primary)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            if (other.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  for (final r in other)
                    ListTile(
                      dense: true,
                      title: Text(r.label, style: const TextStyle(color: muted)),
                      trailing: Text(
                          '${r.value}${r.unit.isEmpty ? '' : ' ${r.unit}'}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
            ],
            for (final w in out.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: w.severe ? const Color(0xFF501313) : const Color(0xFF412402),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        color: w.severe ? const Color(0xFFF09595) : const Color(0xFFFAC775)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(w.text,
                            style: TextStyle(
                                color: w.severe
                                    ? const Color(0xFFF7C1C1)
                                    : const Color(0xFFFAC775)))),
                  ]),
                ),
              ),

            // ---------- Uitleg (fold-out) ----------
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: const Icon(Icons.functions),
                title: const Text('Zo is het berekend'),
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in out.steps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SelectableText(s,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.35,
                              color: Color(0xFFD3D1C7))),
                    ),
                ],
              ),
            ),
          ],
          if (c.disclaimer != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(c.disclaimer!,
                  style: const TextStyle(color: muted, fontSize: 12)),
            ),
        ];
        const pad = EdgeInsets.fromLTRB(16, 0, 16, 32);
        if (box.maxWidth >= 820) {
          // Groot scherm: invoer links, uitkomst en uitleg rechts.
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 380,
                child: ListView(padding: pad, children: inputs)),
            Expanded(child: ListView(padding: pad, children: results)),
          ]);
        }
        return ListView(
            padding: pad,
            children: [...inputs, const SizedBox(height: 12), ...results]);
      }),
    );
  }
}
