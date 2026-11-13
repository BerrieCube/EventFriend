import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../format.dart';
import '../store.dart';
import 'common.dart';

/// Overzicht van gedane klussen per opdrachtgever, voor de geselecteerde
/// weken. Bedoeld als basis voor je eigen facturen.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  int _weeksShown = 12;
  late final Set<DateTime> _selected = {_weekBack(weekStart(DateTime.now()), 1)};

  static DateTime _weekBack(DateTime w, int n) =>
      DateTime(w.year, w.month, w.day - 7 * n);

  List<DateTime> get _weeks {
    final current = weekStart(DateTime.now());
    return [
      for (var i = 0; i < _weeksShown; i++) _weekBack(current, i)
    ];
  }

  String _weekLabel(DateTime w) {
    final end = DateTime(w.year, w.month, w.day + 6);
    return 'Wk ${isoWeek(w)} · ${w.day} ${_mon(w)}–${end.day} ${_mon(end)}';
  }

  String _mon(DateTime d) => dateShort(d).split(' ').last;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final jobs = store.jobs
        .where((j) =>
            j.start.isBefore(now) && _selected.contains(weekStart(j.start)))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final byClient = <String, List<Job>>{};
    for (final j in jobs) {
      byClient.putIfAbsent(store.clientName(j), () => []).add(j);
    }
    final clients = byClient.keys.toList()..sort();
    final weeksText = (_selected.toList()..sort())
        .map((w) => '${isoWeek(w)}')
        .join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Overzicht per opdrachtgever')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const Text(
              'Kies de weken. Je ziet alle klussen die in die weken zijn geweest, '
              'per opdrachtgever. Handig als basis voor je factuur.',
              style: TextStyle(color: muted)),
          const SectionTitle('Weken'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final w in _weeks)
              FilterChip(
                label: Text(_weekLabel(w)),
                selected: _selected.contains(w),
                onSelected: (v) => setState(
                    () => v ? _selected.add(w) : _selected.remove(w)),
              ),
            ActionChip(
              avatar: const Icon(Icons.history, size: 18),
              label: const Text('Eerdere weken'),
              onPressed: () => setState(() => _weeksShown += 12),
            ),
          ]),
          const SizedBox(height: 8),
          if (_selected.isEmpty)
            const EmptyHint(
                icon: Icons.date_range,
                title: 'Kies een of meer weken',
                body: 'Tik hierboven op de weken die je wilt factureren.')
          else if (clients.isEmpty)
            const EmptyHint(
                icon: Icons.event_busy,
                title: 'Geen klussen in deze weken',
                body:
                    'Klussen komen uit je Rentman-agenda\'s en je eigen klussen.')
          else
            for (final c in clients)
              _ClientCard(
                  client: c, jobs: byClient[c]!, weeksText: weeksText),
        ],
      ),
    );
  }
}

String _when(Job j) {
  final sameDayJob = sameDay(j.start, j.end) ||
      (j.end.difference(j.start).inHours < 24 &&
          j.end.hour == 0 &&
          j.end.minute == 0);
  return sameDayJob
      ? '${dateShort(j.start)} ${j.start.year} · ${hm(j.start)}–${hm(j.end)}'
      : '${dateShort(j.start)} ${hm(j.start)} – ${dateShort(j.end)} ${hm(j.end)}';
}

Duration _clocked(Job j) => store.hours
    .where((h) => h.jobKey == j.key && !h.running)
    .fold(Duration.zero, (s, h) => s + h.worked);

class _ClientCard extends StatelessWidget {
  final String client;
  final List<Job> jobs;
  final String weeksText;
  const _ClientCard(
      {required this.client, required this.jobs, required this.weeksText});

  String _asText() {
    final b = StringBuffer('$client – week $weeksText\n\n');
    for (final j in jobs) {
      b.writeln(j.title);
      b.writeln('  ${_when(j)} (${duration(j.end.difference(j.start))})');
      if (j.location.isNotEmpty) b.writeln('  ${j.location}');
      final c = _clocked(j);
      if (c > Duration.zero) b.writeln('  Geklokt: ${duration(c)}');
      b.writeln();
    }
    final total = jobs.fold(Duration.zero, (s, j) => s + j.end.difference(j.start));
    b.writeln('Totaal: ${jobs.length} klus(sen), ${duration(total)} gepland');
    return b.toString();
  }

  Future<void> _pdf() async {
    final doc = pw.Document(title: '$client week $weeksText');
    final grey = PdfColor.fromInt(0xFF666666);
    final total = jobs.fold(Duration.zero, (s, j) => s + j.end.difference(j.start));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (c) => [
        pw.Text(client,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('Overzicht klussen, week $weeksText',
            style: pw.TextStyle(color: grey)),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: ['Datum en tijd', 'Project', 'Locatie', 'Duur'],
          data: [
            for (final j in jobs)
              [_when(j), j.title, j.location, duration(j.end.difference(j.start))]
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 10),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(2.5),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(1),
          },
        ),
        pw.SizedBox(height: 10),
        pw.Text('Totaal: ${jobs.length} klus(sen), ${duration(total)} gepland',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    ));
    final safe = client.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    await Printing.sharePdf(
        bytes: await doc.save(), filename: 'Overzicht $safe week $weeksText.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final total = jobs.fold(Duration.zero, (s, j) => s + j.end.difference(j.start));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(client,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary)),
                      Text('${jobs.length} klus(sen) · ${duration(total)} gepland',
                          style: const TextStyle(color: muted)),
                    ]),
              ),
              IconButton(
                tooltip: 'Kopiëren als tekst',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _asText()));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Gekopieerd')));
                },
              ),
              IconButton(
                  tooltip: 'Delen als PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: _pdf),
            ]),
            const Divider(),
            for (final j in jobs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10, right: 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(j.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                          '${_when(j)} · ${duration(j.end.difference(j.start))}'),
                      if (j.location.isNotEmpty)
                        Text(j.location, style: const TextStyle(color: muted)),
                      if (_clocked(j) > Duration.zero)
                        Text('Geklokt: ${duration(_clocked(j))}',
                            style: const TextStyle(color: muted)),
                    ]),
              ),
          ]),
        ),
      ),
    );
  }
}
