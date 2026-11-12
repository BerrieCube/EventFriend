import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../store.dart';
import 'common.dart';

class HoursScreen extends StatefulWidget {
  const HoursScreen({super.key});

  @override
  State<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends State<HoursScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Lopende werktijd elke 30 s bijwerken.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uren'), actions: const [SettingsAction()]),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Uren toevoegen',
        onPressed: () => editEntry(context),
        child: const Icon(Icons.add),
      ),
      body: StoreBuilder(builder: (context) {
        final entries = store.hours;
        final clock = ClockCard(
            running: store.running,
            todayJob: store.jobsOn(DateTime.now()).firstOrNull);
        // Groeperen per week (maandag als start).
        final weeks = <DateTime, List<TimeEntry>>{};
        for (final e in entries) {
          weeks.putIfAbsent(weekStart(e.start), () => []).add(e);
        }
        final keys = weeks.keys.toList()..sort((a, b) => b.compareTo(a));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            clock,
            if (entries.isEmpty)
              const EmptyHint(
                  icon: Icons.schedule,
                  title: 'Nog geen uren',
                  body:
                      'Klok in met de knop hierboven of voeg uren toe met de +.'),
            for (final w in keys) ...[
              _WeekHeader(start: w, entries: weeks[w]!),
              for (final e in weeks[w]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      title: Text(
                          '${dateShort(e.start)} · ${hm(e.start)}–${e.end == null ? 'nu' : hm(e.end!)}'),
                      subtitle: Text([
                        if (e.jobTitle.isNotEmpty) e.jobTitle,
                        if (e.pauseMin > 0) '${e.pauseMin} min pauze',
                        if (e.km > 0) '${nf(e.km, 0)} km',
                        if (e.note.isNotEmpty) e.note,
                      ].join(' · ')),
                      trailing: Text(duration(e.worked),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: e.running
                                  ? Theme.of(context).colorScheme.primary
                                  : null)),
                      onTap: () => editEntry(context, entry: e),
                    ),
                  ),
                ),
            ],
          ],
        );
      }),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  final DateTime start;
  final List<TimeEntry> entries;
  const _WeekHeader({required this.start, required this.entries});

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<Duration>(Duration.zero, (s, e) => s + e.worked);
    final km = entries.fold<double>(0, (s, e) => s + e.km);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(children: [
        Expanded(
          child: Text('Week ${isoWeek(start)} · vanaf ${dateShort(start)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Text('${duration(total)}${km > 0 ? ' · ${nf(km, 0)} km' : ''}',
            style: const TextStyle(color: muted)),
      ]),
    );
  }
}

Future<void> editEntry(BuildContext context, {TimeEntry? entry}) async {
  final now = DateTime.now();
  final e = entry ??
      TimeEntry(
          id: newId(),
          start: DateTime(now.year, now.month, now.day, 8),
          end: DateTime(now.year, now.month, now.day, 17));
  var start = e.start;
  DateTime? end = e.end;
  final pause = TextEditingController(text: e.pauseMin == 0 ? '' : '${e.pauseMin}');
  final km = TextEditingController(text: e.km == 0 ? '' : nf(e.km, 0));
  final title = TextEditingController(text: e.jobTitle);
  final note = TextEditingController(text: e.note);
  String? error;

  Future<DateTime?> pick(BuildContext c, DateTime base) async {
    final d = await showDatePicker(
        context: c,
        initialDate: base,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (d == null || !c.mounted) return null;
    final t = await showTimePicker(
        context: c, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      return AlertDialog(
        title: Text(entry == null ? 'Uren toevoegen' : 'Uren wijzigen'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.login),
              title: Text('${dateShort(start)} ${hm(start)}'),
              subtitle: const Text('Start'),
              onTap: () async {
                final d = await pick(c, start);
                if (d != null) setS(() => start = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout),
              title: Text(end == null ? 'Loopt nog' : '${dateShort(end!)} ${hm(end!)}'),
              subtitle: const Text('Einde'),
              onTap: () async {
                final d = await pick(c, end ?? DateTime.now());
                if (d != null) setS(() => end = d);
              },
            ),
            TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Klus')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: pause,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Pauze (min)')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    controller: km,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Kilometers')),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Opmerking')),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error)),
              ),
          ]),
        ),
        actions: [
          if (entry != null)
            TextButton(
              onPressed: () {
                store.deleteEntry(e.id);
                Navigator.pop(c);
              },
              child: const Text('Verwijderen'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () {
              if (end != null && !end!.isAfter(start)) {
                setS(() => error = 'Het einde moet na de start liggen.');
                return;
              }
              e.start = start;
              e.end = end;
              e.pauseMin = int.tryParse(pause.text.trim()) ?? 0;
              e.km = parseNum(km.text) ?? 0;
              e.jobTitle = title.text.trim();
              e.note = note.text.trim();
              store.saveEntry(e);
              Navigator.pop(c);
            },
            child: const Text('Opslaan'),
          ),
        ],
      );
    }),
  );
}

class ClockCard extends StatelessWidget {
  final TimeEntry? running;
  final Job? todayJob;
  const ClockCard({required this.running, required this.todayJob});

  @override
  Widget build(BuildContext context) {
    final r = running;
    if (r == null) {
      return SizedBox(
        height: 56,
        child: FilledButton.icon(
          onPressed: () => store.clockIn(job: todayJob),
          icon: const Icon(Icons.login),
          label: const Text('Inklokken',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              'Ingeklokt om ${hm(r.start)}${r.jobTitle.isEmpty ? '' : ' · ${r.jobTitle}'}',
              style: const TextStyle(color: muted)),
          const SizedBox(height: 4),
          Text(duration(r.worked),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE24B4A),
                  foregroundColor: Colors.white),
              onPressed: store.clockOut,
              icon: const Icon(Icons.logout),
              label: const Text('Uitklokken',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}
