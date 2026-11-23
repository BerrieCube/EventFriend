import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/defs.dart';
import '../format.dart';
import '../note_text.dart';
import '../store.dart';
import 'apps.dart';
import 'clock.dart';
import 'common.dart';
import 'docs.dart';
import 'job_detail.dart';
import 'notes.dart';
import 'overview.dart';
import 'tools.dart';

/// Een blok op het dashboard.
class DashItem {
  final String type;
  bool wide;
  final String? ref; // notitie-id, calculator-id of app-id

  DashItem(this.type, {this.wide = false, this.ref});

  Map<String, dynamic> toMap() => {'type': type, 'wide': wide, 'ref': ref};

  factory DashItem.fromMap(Map<String, dynamic> m) =>
      DashItem(m['type'] as String, wide: m['wide'] == true, ref: m['ref']);
}

/// Standaardindeling bij de eerste keer.
List<DashItem> defaultDashboard() => [
      DashItem('clock', wide: true),
      DashItem('today', wide: true),
      DashItem('clock_in'),
      DashItem('to_process'),
      DashItem('tomorrow', wide: true),
      DashItem('quick_note', wide: true),
    ];

/// Alle bloksoorten voor "Blok toevoegen": (type, naam, icoon, groep).
const _catalog = <(String, String, IconData, String)>[
  ('today', 'Klus vandaag', Icons.today, 'Klussen'),
  ('next', 'Volgende klus', Icons.event_outlined, 'Klussen'),
  ('tomorrow', 'Klus van morgen', Icons.event_available_outlined, 'Klussen'),
  ('clock_in', 'In/uitklokken', Icons.play_circle_outline, 'Uren en facturatie'),
  ('to_process', 'Te verwerken', Icons.receipt_long_outlined, 'Uren en facturatie'),
  ('note', 'Notitie kiezen…', Icons.sticky_note_2_outlined, 'Notities'),
  ('quick_note', 'Snel notitie maken', Icons.edit_note, 'Notities'),
  ('clock', 'Klok en datum', Icons.access_time, 'Tools'),
  ('calc', 'Calculator…', Icons.calculate_outlined, 'Tools'),
  ('app', 'App of link…', Icons.apps, 'Tools'),
  ('docs', 'Documenten & links', Icons.folder_open, 'Tools'),
];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _editing = false;

  List<DashItem> get _items =>
      store.dashboard?.map(DashItem.fromMap).toList() ?? defaultDashboard();

  Future<void> _save(List<DashItem> items) =>
      store.setDashboard(items.map((i) => i.toMap()).toList());

  Future<void> _add() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) {
        final groups = <String, List<(String, String, IconData, String)>>{};
        for (final e in _catalog) {
          groups.putIfAbsent(e.$4, () => []).add(e);
        }
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final g in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                      child: Text(g.key,
                          style: const TextStyle(color: muted, fontSize: 12)),
                    ),
                    for (final e in g.value)
                      ListTile(
                        leading: Icon(e.$3),
                        title: Text(e.$2),
                        onTap: () => Navigator.pop(c, e.$1),
                      ),
                  ],
                ]),
          ),
        );
      },
    );
    if (type == null || !mounted) return;
    String? ref;
    if (type == 'note') {
      ref = await _pickNote();
      if (ref == null) return;
    } else if (type == 'calc') {
      ref = await _pick(
          'Calculator',
          [for (final c in calculators) (c.id, '${c.category} · ${c.title}')]);
      if (ref == null) return;
    } else if (type == 'app') {
      final apps = store.allApps.where((a) => !a.isApp || canPickApps).toList();
      if (apps.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Voeg eerst een app of link toe onder Tools.')));
        return;
      }
      ref = await _pick('App of link', [for (final a in apps) (a.id, a.name)]);
      if (ref == null) return;
    }
    final wide = const {'today', 'next', 'tomorrow', 'quick_note', 'clock', 'note'}
        .contains(type);
    await _save([..._items, DashItem(type, wide: wide, ref: ref)]);
  }

  Future<String?> _pick(String title, List<(String, String)> options) =>
      showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(c).height * 0.7),
            child: ListView(shrinkWrap: true, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              for (final o in options)
                ListTile(title: Text(o.$2), onTap: () => Navigator.pop(c, o.$1)),
            ]),
          ),
        ),
      );

  Future<String?> _pickNote() async {
    final ctrl = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, setS) {
        final q = ctrl.text.trim().toLowerCase();
        final notes = store.notes
            .where((n) =>
                (n.space == 'work' || store.privatePin == null || privateUnlocked) &&
                (q.isEmpty ||
                    n.title.toLowerCase().contains(q) ||
                    n.text.toLowerCase().contains(q)))
            .take(50)
            .toList();
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(c).height * 0.75),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Notitie zoeken',
                        isDense: true),
                    onChanged: (_) => setS(() {}),
                  ),
                ),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final n in notes)
                      ListTile(
                        leading: Icon(
                            n.pinned ? Icons.push_pin : Icons.sticky_note_2_outlined,
                            size: 20),
                        title: Text(n.heading,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(store.spaceName(n.space),
                            style: TextStyle(color: spaceColor(n.space))),
                        onTap: () => Navigator.pop(c, n.id),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Dashboard bewerken' : 'Dashboard'),
        actions: _editing
            ? [
                TextButton(
                    onPressed: () => setState(() => _editing = false),
                    child: const Text('Klaar')),
              ]
            : [
                IconButton(
                    tooltip: 'Dashboard bewerken',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => setState(() => _editing = true)),
                const SettingsAction(),
              ],
      ),
      body: StoreBuilder(builder: (context) {
        final items = _items;
        return LayoutBuilder(builder: (context, box) {
          const gap = 8.0, pad = 12.0;
          final cols = (box.maxWidth / 230).floor().clamp(2, 6);
          final unit = (box.maxWidth - pad * 2 - gap * (cols - 1)) / cols;
          double widthOf(DashItem i) => i.wide ? unit * 2 + gap : unit;
          return ListView(
            padding: const EdgeInsets.fromLTRB(pad, 4, pad, 24),
            children: [
              if (items.isEmpty && !_editing)
                EmptyHint(
                  icon: Icons.dashboard_customize_outlined,
                  title: 'Stel je dashboard samen',
                  body: 'Zet hier de onderdelen neer die je het meest gebruikt.',
                  action: FilledButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Bewerken')),
                ),
              Wrap(spacing: gap, runSpacing: gap, children: [
                for (var i = 0; i < items.length; i++)
                  SizedBox(
                    width: widthOf(items[i]),
                    child: _editing
                        ? _editable(items, i, widthOf(items[i]))
                        : _Block(item: items[i]),
                  ),
              ]),
              if (_editing) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Blok toevoegen'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Expanded(
                    child: Text(
                        '${kIsWeb ? 'Sleep een blok' : 'Houd een blok vast en sleep het'} '
                        'naar een andere plek. Met de pijltjes rechtsonder maak je '
                        'een blok breed of smal.',
                        style: TextStyle(color: muted, fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (await confirm(context, 'Standaardindeling terugzetten?',
                          'Je eigen indeling wordt vervangen.',
                          ok: 'Terugzetten')) {
                        await _save(defaultDashboard());
                      }
                    },
                    child: const Text('Standaard'),
                  ),
                ]),
              ],
            ],
          );
        });
      }),
    );
  }

  Widget _editable(List<DashItem> items, int i, double width) {
    final item = items[i];
    final block = Stack(
        clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
      // Absorbeert tikken (blok opent niets tijdens bewerken), maar telt wel
      // als aanraakvlak zodat het blok versleept kan worden.
      AbsorbPointer(
        child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF5A5A5A)),
          ),
          child: _Block(item: item),
        ),
      ),
      Positioned(
        top: -6,
        right: -6,
        child: _RoundButton(
          icon: Icons.close,
          tooltip: 'Verwijderen',
          onTap: () => _save([...items]..removeAt(i)),
        ),
      ),
      Positioned(
        bottom: -6,
        right: -6,
        child: _RoundButton(
          icon: Icons.swap_horiz,
          tooltip: item.wide ? 'Smal maken' : 'Breed maken',
          onTap: () {
            item.wide = !item.wide;
            _save(items);
          },
        ),
      ),
    ]);
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != i,
      onAcceptWithDetails: (d) {
        // Het gesleepte blok neemt de plek in van het blok eronder.
        final l = [...items];
        final moved = l.removeAt(d.data);
        l.insert(i.clamp(0, l.length), moved);
        _save(l);
      },
      builder: (context, cand, _) => AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: cand.isEmpty ? 1 : 0.5,
        child: _dragSource(i, item, width, block),
      ),
    );
  }
}

/// Op het web direct slepen met de muis; op de telefoon lang indrukken
/// (zodat gewoon scrollen blijft werken).
Widget _dragSource(int i, DashItem item, double width, Widget block) {
  final feedback = Material(
    color: Colors.transparent,
    child: SizedBox(
        width: width,
        child: Opacity(opacity: 0.85, child: _Block(item: item))),
  );
  final ghost = Opacity(opacity: 0.3, child: block);
  if (kIsWeb) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<int>(
          data: i, feedback: feedback, childWhenDragging: ghost, child: block),
    );
  }
  return LongPressDraggable<int>(
    data: i,
    onDragStarted: HapticFeedback.selectionClick,
    feedback: feedback,
    childWhenDragging: ghost,
    child: block,
  );
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: const Color(0xFF2E2F33),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(icon, size: 16)),
          ),
        ),
      );
}

// ============================================================ Blokken

class _Block extends StatelessWidget {
  final DashItem item;
  const _Block({required this.item});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    switch (item.type) {
      case 'clock':
        return const _ClockBlock();
      case 'today':
        final jobs = store.jobsOn(now);
        return _JobBlock(
            label: 'Vandaag', job: jobs.firstOrNull, empty: 'Geen klus vandaag',
            more: jobs.length - 1);
      case 'next':
        final j = store.planningJobs.where((j) => j.start.isAfter(now)).firstOrNull;
        return _JobBlock(
            label: j == null ? 'Volgende klus' : 'Volgende · ${dateShort(j.start)}',
            job: j,
            empty: 'Geen klussen gepland');
      case 'tomorrow':
        final day = DateTime(now.year, now.month, now.day + 1);
        final today = store.jobsOn(now).map((j) => j.key).toSet();
        final jobs =
            store.jobsOn(day).where((j) => !today.contains(j.key)).toList();
        return _JobBlock(
            label: 'Morgen · ${dateShort(day)}',
            job: jobs.firstOrNull,
            empty: 'Morgen geen klus',
            more: jobs.length - 1,
            compact: true);
      case 'clock_in':
        // ignore: prefer_const_constructors (moet meebewegen met de opslag)
        return _ClockInBlock(key: ValueKey(store.running?.id));
      case 'to_process':
        final jobs = store.toProcess;
        final clients = jobs.map(store.clientName).toSet().length;
        return _Tile(
          icon: Icons.receipt_long_outlined,
          title: jobs.isEmpty ? 'Alles verwerkt' : '${jobs.length} te verwerken',
          subtitle: jobs.isEmpty
              ? 'Niets te factureren'
              : '$clients opdrachtgever${clients == 1 ? '' : 's'}',
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OverviewScreen())),
        );
      case 'note':
        return _NoteBlock(noteId: item.ref);
      case 'quick_note':
        // ignore: prefer_const_constructors
        return _QuickNoteBlock();
      case 'calc':
        final c = calculators.where((c) => c.id == item.ref).firstOrNull;
        if (c == null) return const _Missing('Calculator bestaat niet meer');
        return _Tile(
          icon: c.icon,
          title: c.title,
          subtitle: c.category,
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => CalcScreen(calc: c))),
        );
      case 'app':
        final a = store.allApps.where((a) => a.id == item.ref).firstOrNull;
        if (a == null) return const _Missing('App of link bestaat niet meer');
        return _Tile(
          icon: a.isApp ? Icons.apps : Icons.link,
          title: a.name,
          subtitle: a.isApp ? 'App' : 'Link',
          onTap: () => launchTile(context, a),
        );
      case 'docs':
        return _Tile(
          icon: Icons.folder_open,
          title: 'Documenten & links',
          subtitle: '${store.libraryDocs.length} items',
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LibraryScreen())),
        );
    }
    return const _Missing('Onbekend blok');
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;
  const _Tile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      color: color,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: primary, size: 26),
            const SizedBox(height: 8),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  final String text;
  const _Missing(this.text);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(text, style: const TextStyle(color: muted)),
        ),
      );
}

class _ClockBlock extends StatefulWidget {
  const _ClockBlock();

  @override
  State<_ClockBlock> createState() => _ClockBlockState();
}

class _ClockBlockState extends State<_ClockBlock> {
  late final Timer _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ClockScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(children: [
            Text(dateLong(n), style: const TextStyle(color: muted, fontSize: 12)),
            FittedBox(
              child: Text('${hm(n)}:${two(n.second)}',
                  style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ]),
        ),
      ),
    );
  }
}

class _JobBlock extends StatelessWidget {
  final String label;
  final Job? job;
  final String empty;
  final int more;
  final bool compact;
  const _JobBlock(
      {required this.label,
      required this.job,
      required this.empty,
      this.more = 0,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final j = job;
    final primary = Theme.of(context).colorScheme.primary;
    if (j == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(empty, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }
    final docs = store.docsFor(j.key);
    final phones = j.phoneNumbers;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openJob(context, j.key),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: muted, fontSize: 12)),
                    ClientLabel(j, size: 12),
                    Text(j.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(
                        [
                          '${hm(j.start)}–${hm(j.end)}',
                          if (j.location.isNotEmpty) j.location,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted)),
                    if (!compact && (docs.isNotEmpty || phones.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 6, runSpacing: 6, children: [
                          if (docs.isNotEmpty)
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.description_outlined, size: 16),
                              label: const Text('Callsheet'),
                              onPressed: () =>
                                  openDoc(context, docs.first, siblings: docs),
                            ),
                          if (phones.isNotEmpty)
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.phone_outlined, size: 16),
                              label: const Text('Bellen'),
                              onPressed: () => callNumber(phones.first),
                            ),
                        ]),
                      ),
                    if (more > 0)
                      Text('+ $more andere klus${more == 1 ? '' : 'sen'}',
                          style: const TextStyle(color: muted, fontSize: 12)),
                  ]),
            ),
            if (j.location.isNotEmpty)
              IconButton(
                tooltip: 'Route',
                iconSize: 28,
                color: primary,
                icon: const Icon(Icons.navigation_outlined),
                onPressed: () => openRoute(context, j.location),
              ),
          ]),
        ),
      ),
    );
  }
}

class _ClockInBlock extends StatefulWidget {
  const _ClockInBlock({super.key});

  @override
  State<_ClockInBlock> createState() => _ClockInBlockState();
}

class _ClockInBlockState extends State<_ClockInBlock> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = store.running;
    final primary = Theme.of(context).colorScheme.primary;
    if (r == null) {
      final job = store.jobsOn(DateTime.now()).firstOrNull;
      return _Tile(
        icon: Icons.play_circle_outline,
        title: 'Inklokken',
        subtitle: job?.title ?? 'Zonder klus',
        color: primary.withValues(alpha: 0.16),
        onTap: () async {
          await store.clockIn(job: job);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ingeklokt om ${hm(DateTime.now())}')));
          }
        },
      );
    }
    return _Tile(
      icon: Icons.stop_circle_outlined,
      title: 'Uitklokken · ${duration(r.worked)}',
      subtitle: 'Sinds ${hm(r.start)}${r.jobTitle.isEmpty ? '' : ' · ${r.jobTitle}'}',
      color: const Color(0xFFE24B4A).withValues(alpha: 0.18),
      onTap: () async {
        if (await confirm(context, 'Uitklokken?',
            'Je hebt ${duration(r.worked)} gewerkt.',
            ok: 'Uitklokken')) {
          await store.clockOut();
        }
      },
    );
  }
}

/// Notitie op het dashboard; checklist-items zijn hier direct af te vinken.
class _NoteBlock extends StatelessWidget {
  final String? noteId;
  const _NoteBlock({required this.noteId});

  @override
  Widget build(BuildContext context) {
    final n = noteId == null ? null : store.note(noteId!);
    if (n == null || n.trashed != null) {
      return const _Missing('Notitie bestaat niet meer');
    }
    if (n.space != 'work' && store.privatePin != null && !privateUnlocked) {
      return Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            if (await unlockPrivate(context)) store.refresh();
          },
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.lock_outline, color: muted),
              SizedBox(width: 8),
              Expanded(child: Text('Vergrendelde notitie · tik om te openen')),
            ]),
          ),
        ),
      );
    }
    final lines = n.content != null ? linesOf(n.content) : <NoteLine>[];
    final open = <(int, NoteLine)>[
      for (var i = 0; i < lines.length; i++)
        if (!lines[i].isChecked) (i, lines[i])
    ];
    final checked = lines.where((l) => l.isChecked).length;
    final plainLines = n.content == null
        ? n.text.split('\n').where((l) => !l.startsWith('☑')).take(10).toList()
        : null;

    Future<void> toggle(int index) async {
      final c = n.content;
      if (c == null) return;
      n.content = setLineChecked(c, index, true);
      n.text = deltaToPlain(n.content);
      await store.saveNote(n);
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => editNote(context, note: n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(n.title.trim().isEmpty ? 'Notitie' : n.title.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              if (n.pinned)
                Icon(Icons.push_pin,
                    size: 14, color: Theme.of(context).colorScheme.primary),
            ]),
            const SizedBox(height: 4),
            if (plainLines != null)
              for (final l in plainLines)
                Text(l, maxLines: 3, overflow: TextOverflow.ellipsis)
            else
              for (final (i, l) in open.take(12))
                l.isUnchecked
                    ? InkWell(
                        onTap: () => toggle(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            const Icon(Icons.check_box_outline_blank,
                                size: 20, color: muted),
                            const SizedBox(width: 8),
                            Expanded(child: Text(l.plain)),
                          ]),
                        ),
                      )
                    : l.plain.trim().isEmpty
                        ? const SizedBox(height: 6)
                        : Text(
                            '${l.list == 'bullet' ? '• ' : ''}${l.plain}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
            if (open.length > 12)
              const Text('…', style: TextStyle(color: muted)),
            if (checked > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    checked == 1
                        ? '+ 1 afgevinkt item'
                        : '+ $checked afgevinkte items',
                    style: const TextStyle(color: muted, fontSize: 12)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _QuickNoteBlock extends StatelessWidget {
  const _QuickNoteBlock();

  @override
  Widget build(BuildContext context) {
    final space = store.notesSpace == 'all' ? 'work' : store.notesSpace;
    void go({bool checklist = false, bool photo = false}) async {
      if (space != 'work' && !await unlockPrivate(context)) return;
      if (!context.mounted) return;
      editNote(context, space: space, checklist: checklist, photo: photo);
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: go,
        child: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Row(children: [
            const Expanded(
                child: Text('Notitie maken…',
                    style: TextStyle(color: muted, fontSize: 15))),
            Text(store.spaceName(space),
                style: TextStyle(color: spaceColor(space), fontSize: 12)),
            IconButton(
                tooltip: 'Nieuwe checklist',
                icon: const Icon(Icons.check_box_outlined),
                onPressed: () => go(checklist: true)),
            IconButton(
                tooltip: 'Nieuwe notitie met afbeelding',
                icon: const Icon(Icons.image_outlined),
                onPressed: () => go(photo: true)),
          ]),
        ),
      ),
    );
  }
}
