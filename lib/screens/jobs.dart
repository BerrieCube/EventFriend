import 'package:flutter/material.dart';

import '../format.dart';
import '../store.dart';
import '../sync.dart';
import 'calendars.dart';
import 'common.dart';
import 'job_detail.dart';
import 'overview.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  bool _calendar = false;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Klussen'),
          actions: [
            IconButton(
              tooltip: _calendar ? 'Lijstweergave' : 'Maandkalender',
              icon: Icon(_calendar
                  ? Icons.view_agenda_outlined
                  : Icons.calendar_view_month),
              onPressed: () => setState(() => _calendar = !_calendar),
            ),
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
                PopupMenuItem(
                    value: 'job', child: Text('Eigen klus toevoegen')),
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
          bottom: _calendar
              ? null
              : TabBar(tabs: [
                  const Tab(text: 'Komend'),
                  Tab(
                    child: StoreBuilder(builder: (context) {
                      final n = store.toProcess.length;
                      return Row(mainAxisSize: MainAxisSize.min, children: [
                        const Flexible(
                            child: Text('Te verwerken',
                                overflow: TextOverflow.ellipsis)),
                        if (n > 0) ...[
                          const SizedBox(width: 6),
                          Badge(label: Text('$n')),
                        ],
                      ]);
                    }),
                  ),
                  const Tab(text: 'Afgelopen'),
                ]),
        ),
        body: StoreBuilder(builder: (context) {
          if (_calendar) return const MonthView();
          final now = DateTime.now();
          final all = store.jobs;
          final coming = store.planningJobs
              .where((j) => j.end.isAfter(now))
              .toList();
          final past =
              all.where((j) => !j.end.isAfter(now)).toList().reversed.toList();
          return TabBarView(children: [
            _JobList(jobs: coming, emptyText: 'Geen komende klussen.'),
            const _ToProcess(),
            _JobList(
                jobs: past,
                emptyText: 'Nog geen afgelopen klussen.',
                showInvoiced: true),
          ]);
        }),
      ),
    );
  }
}

Future<void> _refresh() async {
  await sync.run();
  await store.syncAll();
}

/// Kaart van één klus in een lijst.
class JobCard extends StatelessWidget {
  final Job job;
  final bool showInvoiced;
  final bool showDate;
  final Widget? trailing;
  const JobCard(
      {super.key,
      required this.job,
      this.showInvoiced = false,
      this.showDate = false,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    final j = job;
    final notes = store.notesFor(j.key).length;
    final photos = store.photosFor(j.key).length;
    final invoiced = showInvoiced && store.isInvoiced(j);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClientLabel(j),
            Text(j.title),
          ]),
          subtitle: Text([
            if (showDate) '${dateShort(j.start)} · wk ${isoWeek(j.start)}',
            '${hm(j.start)}–${hm(j.end)}',
            if (j.location.isNotEmpty) j.location,
          ].join(' · ')),
          trailing: trailing ??
              ((notes + photos) > 0 || invoiced
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      if (notes > 0) ...[
                        const Icon(Icons.notes, size: 16, color: muted),
                        Text(' $notes  ', style: const TextStyle(color: muted)),
                      ],
                      if (photos > 0) ...[
                        const Icon(Icons.photo_outlined,
                            size: 16, color: muted),
                        Text(' $photos  ',
                            style: const TextStyle(color: muted)),
                      ],
                      if (invoiced)
                        const Tooltip(
                            message: 'Gefactureerd',
                            child:
                                Icon(Icons.task_alt, size: 16, color: muted)),
                    ])
                  : const Icon(Icons.chevron_right)),
          onTap: () => openJob(context, j.key),
        ),
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  final List<Job> jobs;
  final String emptyText;
  final bool showInvoiced;
  const _JobList(
      {required this.jobs, required this.emptyText, this.showInvoiced = false});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDay)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                        child: Text(
                            '${dateLong(j.start)} · wk ${isoWeek(j.start)}',
                            style: const TextStyle(color: muted)),
                      ),
                    JobCard(job: j, showInvoiced: showInvoiced),
                  ],
                );
              },
            ),
    );
  }
}

/// Afgelopen klussen die nog gefactureerd moeten worden, per opdrachtgever.
class _ToProcess extends StatelessWidget {
  const _ToProcess();

  @override
  Widget build(BuildContext context) {
    final jobs = store.toProcess;
    final byClient = <String, List<Job>>{};
    for (final j in jobs) {
      byClient.putIfAbsent(store.clientName(j), () => []).add(j);
    }
    final clients = byClient.keys.toList()..sort();
    if (clients.isEmpty) {
      return ListView(children: const [
        EmptyHint(
          icon: Icons.task_alt,
          title: 'Niets te verwerken',
          body:
              'Afgelopen klussen komen hier tot je ze als gefactureerd markeert.',
        )
      ]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final c in clients) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 0, 6),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary)),
                      Text('${byClient[c]!.length} klus(sen) te factureren',
                          style: const TextStyle(color: muted)),
                    ]),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OverviewScreen(client: c))),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Factureren'),
              ),
            ]),
          ),
          for (final j in byClient[c]!.reversed)
            JobCard(
              job: j,
              showDate: true,
              trailing: IconButton(
                tooltip: 'Markeer als gefactureerd',
                icon: const Icon(Icons.task_alt_outlined),
                onPressed: () {
                  store.setInvoiced([j], true);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        persist: false,
                    content: Text('"${j.title}" gemarkeerd als gefactureerd'),
                    action: SnackBarAction(
                        label: 'Ongedaan',
                        onPressed: () => store.setInvoiced([j], false)),
                  ));
                },
              ),
            ),
        ],
      ],
    );
  }
}

/// Maandkalender met stipjes op dagen met een klus.
class MonthView extends StatefulWidget {
  const MonthView({super.key});

  @override
  State<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<MonthView> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _day = dayStart(DateTime.now());

  void _shift(int n) =>
      setState(() => _month = DateTime(_month.year, _month.month + n));

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final today = dayStart(DateTime.now());
    final first = weekStart(_month);
    final days = [
      for (var i = 0; i < 42; i++)
        DateTime(first.year, first.month, first.day + i)
    ];
    // Klussen per dag (meerdaagse klussen op elke dag).
    final perDay = <DateTime, int>{};
    for (final j in store.planningJobs) {
      if (j.end.isBefore(days.first) ||
          j.start.isAfter(days.last.add(const Duration(days: 1)))) {
        continue;
      }
      var d = dayStart(j.start);
      final last = j.end.subtract(const Duration(seconds: 1));
      while (!d.isAfter(last)) {
        perDay[d] = (perDay[d] ?? 0) + 1;
        d = DateTime(d.year, d.month, d.day + 1);
      }
    }
    final selected = store.jobsOn(_day);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              Row(children: [
                IconButton(
                    tooltip: 'Vorige maand',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _shift(-1)),
                Expanded(
                  child: Text(monthYear(_month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                    tooltip: 'Volgende maand',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _shift(1)),
              ]),
              TextButton(
                onPressed: () => setState(() {
                  _month = DateTime(today.year, today.month);
                  _day = today;
                }),
                child: const Text('Vandaag'),
              ),
              Row(children: [
                const SizedBox(width: 28),
                for (final w in weekdayShort)
                  Expanded(
                      child: Text(w,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: muted, fontSize: 12))),
              ]),
              const SizedBox(height: 4),
              for (var r = 0; r < 6; r++)
                Row(children: [
                  SizedBox(
                    width: 28,
                    child: Text('${isoWeek(days[r * 7])}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: muted, fontSize: 10)),
                  ),
                  for (var c = 0; c < 7; c++)
                    Expanded(
                        child: _cell(days[r * 7 + c], perDay, today, primary)),
                ]),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text('${dateLong(_day)} · wk ${isoWeek(_day)}',
                    style: const TextStyle(color: muted)),
              ),
              if (selected.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text('Geen klussen op deze dag.',
                      style: TextStyle(color: muted)),
                ),
              for (final j in selected) JobCard(job: j, showInvoiced: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(
      DateTime d, Map<DateTime, int> perDay, DateTime today, Color primary) {
    final inMonth = d.month == _month.month;
    final isSel = d == _day;
    final n = perDay[d] ?? 0;
    return AspectRatio(
      aspectRatio: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          _day = d;
          if (!inMonth) _month = DateTime(d.year, d.month);
        }),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSel ? primary.withValues(alpha: 0.22) : null,
            border: d == today ? Border.all(color: primary) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${d.day}',
                style: TextStyle(
                    color: inMonth ? null : muted.withValues(alpha: 0.5),
                    fontWeight: n > 0 ? FontWeight.w600 : null)),
            const SizedBox(height: 3),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < n.clamp(0, 3); i++)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                      color: inMonth ? primary : muted, shape: BoxShape.circle),
                ),
            ]),
          ]),
        ),
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
                decoration:
                    const InputDecoration(labelText: 'Omschrijving / contact')),
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
                    final t =
                        await showTimePicker(context: c, initialTime: end);
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
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuleren')),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) {
                setS(() => error = 'Geef de klus een titel.');
                return;
              }
              final s = DateTime(
                  day.year, day.month, day.day, start.hour, start.minute);
              var e =
                  DateTime(day.year, day.month, day.day, end.hour, end.minute);
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
