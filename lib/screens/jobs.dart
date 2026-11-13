import 'package:flutter/material.dart';

import '../format.dart';
import '../store.dart';
import '../sync.dart';
import 'calendars.dart';
import 'common.dart';
import 'job_detail.dart';
import 'overview.dart';

class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Klussen'),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.add),
              tooltip: 'Toevoegen',
              onSelected: (v) {
                if (v == 'cal') showAddCalendar(context);
                if (v == 'job') editManualJob(context);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'cal', child: Text('Rentman-agenda toevoegen')),
                PopupMenuItem(value: 'job', child: Text('Eigen klus toevoegen')),
              ],
            ),
            IconButton(
              tooltip: 'Overzicht per opdrachtgever',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OverviewScreen())),
            ),
            const SettingsAction(),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Komend'), Tab(text: 'Afgelopen')]),
        ),
        body: StoreBuilder(builder: (context) {
          final now = DateTime.now();
          final today = dayStart(now);
          final all = store.jobs;
          final coming = all.where((j) => j.end.isAfter(today)).toList();
          final past = all.where((j) => !j.end.isAfter(today)).toList().reversed.toList();
          return TabBarView(children: [
            _JobList(jobs: coming, emptyText: 'Geen komende klussen.'),
            _JobList(jobs: past, emptyText: 'Nog geen afgelopen klussen.'),
          ]);
        }),
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  final List<Job> jobs;
  final String emptyText;
  const _JobList({required this.jobs, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
            await sync.run();
            await store.syncAll();
          },
      child: jobs.isEmpty
          ? ListView(children: [
              EmptyHint(
                icon: Icons.event_note_outlined,
                title: emptyText,
                body: store.calendars.isEmpty
                    ? 'Voeg een Rentman-agenda toe via de + rechtsboven.'
                    : 'Trek naar beneden om te verversen.',
              )
            ])
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: jobs.length,
              itemBuilder: (context, i) {
                final j = jobs[i];
                final showDay = i == 0 || !sameDay(jobs[i - 1].start, j.start);
                final notes = store.notesFor(j.key).length;
                final photos = store.photosFor(j.key).length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDay)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                        child: Text(dateLong(j.start),
                            style: const TextStyle(color: muted)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClientLabel(j),
                                Text(j.title),
                              ]),
                          subtitle: Text([
                            '${hm(j.start)}–${hm(j.end)}',
                            if (j.location.isNotEmpty) j.location,
                          ].join(' · ')),
                          trailing: (notes + photos) > 0
                              ? Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (notes > 0) ...[
                                    const Icon(Icons.notes, size: 16, color: muted),
                                    Text(' $notes  ',
                                        style: const TextStyle(color: muted)),
                                  ],
                                  if (photos > 0) ...[
                                    const Icon(Icons.photo_outlined,
                                        size: 16, color: muted),
                                    Text(' $photos',
                                        style: const TextStyle(color: muted)),
                                  ],
                                ])
                              : const Icon(Icons.chevron_right),
                          onTap: () => openJob(context, j.key),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// Eigen klus (buiten Rentman) aanmaken of wijzigen.
Future<void> editManualJob(BuildContext context, {Job? job}) async {
  final title = TextEditingController(text: job?.title ?? '');
  final loc = TextEditingController(text: job?.location ?? '');
  final desc = TextEditingController(text: job?.description ?? '');
  var day = job?.start ?? DateTime.now();
  var start = TimeOfDay.fromDateTime(job?.start ?? DateTime(2000, 1, 1, 8));
  var end = TimeOfDay.fromDateTime(job?.end ?? DateTime(2000, 1, 1, 18));
  String? error;

  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      return AlertDialog(
        title: Text(job == null ? 'Eigen klus' : 'Klus wijzigen'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Titel')),
            const SizedBox(height: 8),
            TextField(
                controller: loc,
                decoration: const InputDecoration(labelText: 'Locatie')),
            const SizedBox(height: 8),
            TextField(
                controller: desc,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Omschrijving / contact')),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.today),
              title: Text(dateLong(day)),
              onTap: () async {
                final d = await showDatePicker(
                    context: c,
                    initialDate: day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (d != null) setS(() => day = d);
              },
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t =
                        await showTimePicker(context: c, initialTime: start);
                    if (t != null) setS(() => start = t);
                  },
                  child: Text('Start ${two(start.hour)}:${two(start.minute)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: c, initialTime: end);
                    if (t != null) setS(() => end = t);
                  },
                  child: Text('Einde ${two(end.hour)}:${two(end.minute)}'),
                ),
              ),
            ]),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error)),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) {
                setS(() => error = 'Geef de klus een titel.');
                return;
              }
              final s = DateTime(
                  day.year, day.month, day.day, start.hour, start.minute);
              var e = DateTime(day.year, day.month, day.day, end.hour, end.minute);
              if (!e.isAfter(s)) e = e.add(const Duration(days: 1));
              store.saveManualJob(Job(
                key: job?.key ?? 'manual|${newId()}',
                calId: 'manual',
                title: title.text.trim(),
                location: loc.text.trim(),
                description: desc.text.trim(),
                start: s,
                end: e,
              ));
              Navigator.pop(c);
            },
            child: const Text('Opslaan'),
          ),
        ],
      );
    }),
  );
}
