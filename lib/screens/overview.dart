import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../format.dart';
import '../pdf_theme.dart';
import '../store.dart';
import 'common.dart';
import 'job_detail.dart';

/// Overzicht van klussen per opdrachtgever: alles wat nog gefactureerd moet
/// worden, of de klussen in gekozen weken. Basis voor je eigen facturen.
class OverviewScreen extends StatefulWidget {
  /// true: start in "Te factureren"; anders in "Per week".
  final bool pending;

  /// Alleen deze opdrachtgever tonen (null = allemaal).
  final String? client;
  const OverviewScreen({super.key, this.pending = true, this.client});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

DateTime _weekBack(DateTime w, int n) => DateTime(w.year, w.month, w.day - 7 * n);

class _OverviewScreenState extends State<OverviewScreen> {
  late bool _pending = widget.pending;
  int _weeksShown = 12;
  late final Set<DateTime> _selected = {_weekBack(weekStart(DateTime.now()), 1)};

  List<DateTime> get _weeks {
    final current = weekStart(DateTime.now());
    return [for (var i = 0; i < _weeksShown; i++) _weekBack(current, i)];
  }

  String _weekLabel(DateTime w) {
    final end = DateTime(w.year, w.month, w.day + 6);
    return 'Wk ${isoWeek(w)} · ${w.day} ${_mon(w)}–${end.day} ${_mon(end)}';
  }

  String _mon(DateTime d) => dateShort(d).split(' ').last;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.client ?? 'Overzicht per opdrachtgever')),
      body: StoreBuilder(builder: (context) {
        final now = DateTime.now();
        final jobs = (_pending
                ? store.toProcess
                : store.jobs.where((j) =>
                    j.start.isBefore(now) &&
                    _selected.contains(weekStart(j.start))))
            .where((j) =>
                widget.client == null || store.clientName(j) == widget.client)
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
        final byClient = <String, List<Job>>{};
        for (final j in jobs) {
          byClient.putIfAbsent(store.clientName(j), () => []).add(j);
        }
        final clients = byClient.keys.toList()..sort();
        final weeks = (_pending
                ? jobs.map((j) => weekStart(j.start)).toSet().toList()
                : _selected.toList())
          ..sort();
        final weeksText = weeks.map((w) => '${isoWeek(w)}').join(', ');

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: true,
                    icon: Icon(Icons.pending_actions_outlined),
                    label: Text('Te factureren')),
                ButtonSegment(
                    value: false,
                    icon: Icon(Icons.date_range),
                    label: Text('Per week')),
              ],
              selected: {_pending},
              onSelectionChanged: (s) => setState(() => _pending = s.first),
            ),
            const SizedBox(height: 10),
            Text(
                _pending
                    ? 'Alle afgelopen klussen die je nog niet als gefactureerd hebt gemarkeerd.'
                    : 'Kies de weken. Je ziet alle klussen die in die weken zijn geweest.',
                style: const TextStyle(color: muted)),
            if (!_pending) ...[
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
            ],
            const SizedBox(height: 8),
            if (!_pending && _selected.isEmpty)
              const EmptyHint(
                  icon: Icons.date_range,
                  title: 'Kies een of meer weken',
                  body: 'Tik hierboven op de weken die je wilt factureren.')
            else if (clients.isEmpty)
              EmptyHint(
                  icon: _pending ? Icons.task_alt : Icons.event_busy,
                  title: _pending
                      ? 'Alles is gefactureerd'
                      : 'Geen klussen in deze weken',
                  body: _pending
                      ? 'Nieuwe klussen verschijnen hier zodra ze voorbij zijn.'
                      : 'Klussen komen uit je Rentman-agenda\'s en je eigen klussen.')
            else
              for (final c in clients)
                ClientCard(
                    client: c,
                    jobs: byClient[c]!,
                    weeksText: weeksText),
          ],
        );
      }),
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

Duration _planned(Job j) => j.end.difference(j.start);

/// Kaart met de klussen van één opdrachtgever, te kopiëren of als PDF.
class ClientCard extends StatelessWidget {
  final String client;
  final List<Job> jobs;
  final String weeksText;
  const ClientCard(
      {super.key,
      required this.client,
      required this.jobs,
      required this.weeksText});

  String get _period => 'week $weeksText';

  double get _km => jobs.fold(0.0, (s, j) => s + store.kmFor(j));
  double get _exp => jobs.fold(0.0, (s, j) => s + store.meta(j.key).expenses);
  Duration get _total => jobs.fold(Duration.zero, (s, j) => s + _planned(j));

  String _extras(Job j) {
    final m = store.meta(j.key);
    final km = store.kmFor(j);
    return [
      if (km > 0) '${nf(km, 0)} km',
      if (m.parking > 0) 'parkeren ${euro(m.parking)}',
      if (m.costs > 0)
        '${m.costNote.isEmpty ? 'onkosten' : m.costNote} ${euro(m.costs)}',
    ].join(' · ');
  }

  String _totals() => [
        '${jobs.length} klus(sen)',
        '${duration(_total)} gepland',
        if (_km > 0) '${nf(_km, 0)} km',
        if (_exp > 0) '${euro(_exp)} onkosten',
      ].join(' · ');

  String _asText() {
    final b = StringBuffer('$client – $_period\n\n');
    for (final j in jobs) {
      b.writeln(j.title);
      b.writeln('  Wk ${isoWeek(j.start)} · ${_when(j)} (${duration(_planned(j))})');
      if (j.location.isNotEmpty) b.writeln('  ${j.location}');
      final c = _clocked(j);
      if (c > Duration.zero) b.writeln('  Geklokt: ${duration(c)}');
      final e = _extras(j);
      if (e.isNotEmpty) b.writeln('  $e');
      b.writeln();
    }
    b.writeln('Totaal: ${_totals()}');
    return b.toString();
  }

  Future<void> _pdf() async {
    final doc = pw.Document(title: '$client $_period');
    final grey = PdfColor.fromInt(0xFF666666);
    final withKm = _km > 0, withExp = _exp > 0;
    doc.addPage(pw.MultiPage(
      theme: await pdfTheme(),
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (c) => [
        pw.Text(client,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('Overzicht klussen, $_period', style: pw.TextStyle(color: grey)),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: [
            'Wk',
            'Datum en tijd',
            'Project',
            'Locatie',
            'Duur',
            if (withKm) 'Km',
            if (withExp) 'Onkosten',
          ],
          data: [
            for (final j in jobs)
              [
                '${isoWeek(j.start)}',
                _when(j),
                j.title,
                j.location,
                duration(_planned(j)),
                if (withKm) store.kmFor(j) > 0 ? nf(store.kmFor(j), 0) : '',
                if (withExp)
                  store.meta(j.key).expenses > 0
                      ? euro(store.meta(j.key).expenses)
                      : '',
              ]
          ],
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          columnWidths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FlexColumnWidth(2.2),
            2: const pw.FlexColumnWidth(2.4),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FlexColumnWidth(1),
            if (withKm) 5: const pw.FlexColumnWidth(0.7),
            if (withExp) (withKm ? 6 : 5): const pw.FlexColumnWidth(1),
          },
        ),
        pw.SizedBox(height: 10),
        pw.Text('Totaal: ${_totals()}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        if (jobs.any((j) => store.meta(j.key).costNote.isNotEmpty)) ...[
          pw.SizedBox(height: 10),
          pw.Text('Onkosten', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          for (final j in jobs)
            if (store.meta(j.key).expenses > 0)
              pw.Text('${dateShort(j.start)} ${j.title}: ${_extras(j)}',
                  style: const pw.TextStyle(fontSize: 9)),
        ],
      ],
    ));
    final safe = client.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    await Printing.sharePdf(
        bytes: await doc.save(), filename: 'Overzicht $safe $_period.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final allInvoiced = jobs.every(store.isInvoiced);
    final primary = Theme.of(context).colorScheme.primary;
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
                              color: primary)),
                      Text(_totals(), style: const TextStyle(color: muted)),
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
              InkWell(
                onTap: () => openJob(context, j.key),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10, right: 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(j.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    'Wk ${isoWeek(j.start)} · ${_when(j)} · ${duration(_planned(j))}'),
                                if (j.location.isNotEmpty)
                                  Text(j.location,
                                      style: const TextStyle(color: muted)),
                                if (_clocked(j) > Duration.zero)
                                  Text('Geklokt: ${duration(_clocked(j))}',
                                      style: const TextStyle(color: muted)),
                                if (_extras(j).isNotEmpty)
                                  Text(_extras(j),
                                      style: const TextStyle(color: muted)),
                              ]),
                        ),
                        if (store.isInvoiced(j))
                          const Tooltip(
                            message: 'Gefactureerd',
                            child: Icon(Icons.task_alt, size: 18, color: muted),
                          ),
                      ]),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: allInvoiced
                    ? TextButton.icon(
                        onPressed: () => store.setInvoiced(jobs, false),
                        icon: const Icon(Icons.undo, size: 18),
                        label: const Text('Gefactureerd · terugzetten'))
                    : FilledButton.tonalIcon(
                        onPressed: () async {
                          if (await confirm(
                              context,
                              'Als gefactureerd markeren?',
                              '${jobs.length} klus(sen) van $client gaan van '
                                  '"Te verwerken" naar "Afgelopen". '
                                  'Terugzetten kan altijd.',
                              ok: 'Markeren')) {
                            await store.setInvoiced(jobs, true);
                          }
                        },
                        icon: const Icon(Icons.task_alt, size: 18),
                        label: const Text('Markeer als gefactureerd')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
