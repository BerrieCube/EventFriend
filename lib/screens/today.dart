import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../store.dart';
import '../sync.dart';
import 'calendars.dart';
import 'common.dart';
import 'job_detail.dart';

class TodayScreen extends StatefulWidget {
  final VoidCallback onOpenJobs;
  const TodayScreen({super.key, required this.onOpenJobs});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Lopende klok elke 30 s bijwerken.
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
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vandaag'),
        actions: const [SettingsAction()],
      ),
      body: StoreBuilder(builder: (context) {
        final today = store.jobsOn(now);
        final upcoming =
            store.jobs.where((j) => j.start.isAfter(now)).take(3).toList();
        return RefreshIndicator(
          onRefresh: () async {
            await sync.run();
            await store.syncAll();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(dateLong(now), style: const TextStyle(color: muted)),
              const SizedBox(height: 8),
              if (store.calendars.isEmpty)
                Card(
                  child: EmptyHint(
                    icon: Icons.link,
                    title: 'Koppel Rentman',
                    body:
                        'Voeg de iCal-link van een opdrachtgever toe, dan zie je hier je klus van vandaag.',
                    action: FilledButton.icon(
                        onPressed: () => showAddCalendar(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Agenda toevoegen')),
                  ),
                )
              else if (today.isEmpty)
                const Card(
                  child: EmptyHint(
                      icon: Icons.free_breakfast_outlined,
                      title: 'Geen klus vandaag',
                      body: 'Hieronder zie je wat er aankomt.'),
                ),
              for (final j in today) ...[
                _TodayJob(job: j),
                const SizedBox(height: 12),
              ],
              if (upcoming.isNotEmpty) ...[
                SectionTitle('Binnenkort',
                    trailing: TextButton(
                        onPressed: widget.onOpenJobs,
                        child: const Text('Alle klussen'))),
                for (final j in upcoming)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClientLabel(j),
                              Text(j.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ]),
                        subtitle: Text(
                            '${dateShort(j.start)} · ${hm(j.start)}${j.location.isEmpty ? '' : ' · ${j.location}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openJob(context, j.key),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _TodayJob extends StatelessWidget {
  final Job job;
  const _TodayJob({required this.job});

  @override
  Widget build(BuildContext context) {
    final amber = Theme.of(context).colorScheme.primary;
    final phones = job.phoneNumbers;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => openJob(context, job.key),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClientLabel(job, size: 13),
                  const SizedBox(height: 2),
                  Text(job.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  if (job.location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.place_outlined, size: 16, color: muted),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(job.location,
                              style: const TextStyle(color: muted))),
                    ]),
                  ],
                ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Start', style: TextStyle(color: muted, fontSize: 12)),
                Text(hm(job.start),
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w600, color: amber)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Einde', style: TextStyle(color: muted, fontSize: 12)),
                Text(hm(job.end),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        if (job.location.isNotEmpty)
          Expanded(
            child: _BigButton(
                icon: Icons.navigation_outlined,
                label: 'Route',
                onTap: () => openRoute(context, job.location)),
          ),
        if (job.location.isNotEmpty && phones.isNotEmpty)
          const SizedBox(width: 8),
        if (phones.isNotEmpty)
          Expanded(
            child: _BigButton(
                icon: Icons.phone_outlined,
                label: 'Bellen',
                onTap: () => callNumber(phones.first)),
          ),
      ]),
    ]);
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BigButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              Icon(icon),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: muted)),
            ]),
          ),
        ),
      );
}
