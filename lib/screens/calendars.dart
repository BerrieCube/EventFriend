import 'package:flutter/material.dart';

import '../format.dart';
import '../store.dart';
import 'common.dart';

/// Opent het venster om een (nieuwe) Rentman-agenda toe te voegen.
/// Overal in de app aan te roepen.
Future<void> showAddCalendar(BuildContext context, {CalendarSource? edit}) {
  return showDialog(
      context: context, builder: (_) => _CalendarDialog(edit: edit));
}

class _CalendarDialog extends StatefulWidget {
  final CalendarSource? edit;
  const _CalendarDialog({this.edit});

  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends State<_CalendarDialog> {
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late final _url = TextEditingController(text: widget.edit?.url ?? '');
  late bool _personal = widget.edit?.personal ?? false;
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Geef de agenda een naam, bijvoorbeeld de opdrachtgever.');
      return;
    }
    final lower = url.toLowerCase();
    if (!(lower.startsWith('https://') ||
        lower.startsWith('http://') ||
        lower.startsWith('webcal://'))) {
      setState(() => _error = 'Plak de volledige iCal-link (begint met https:// of webcal://).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final e = widget.edit;
    if (e == null) {
      await store.addCalendar(name, url, personal: _personal);
    } else {
      e.name = name;
      e.url = url;
      e.personal = _personal;
      await store.updateCalendar(e);
      await store.syncCalendar(e);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.edit == null ? 'Agenda toevoegen' : 'Agenda wijzigen'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  icon: Icon(Icons.business_center_outlined),
                  label: Text('Opdrachtgever')),
              ButtonSegment(
                  value: true,
                  icon: Icon(Icons.person_outline),
                  label: Text('Persoonlijk')),
            ],
            selected: {_personal},
            onSelectionChanged: (v) => setState(() => _personal = v.first),
          ),
          const SizedBox(height: 4),
          Text(
              _personal
                  ? 'Afspraken zie je in je planning, maar ze tellen niet mee voor facturen.'
                  : 'Klussen tellen mee in Te verwerken en het overzicht voor je facturen.',
              style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Naam', hintText: 'Verhuurbedrijf X'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
                labelText: 'iCal-link (Rentman of Google Agenda)',
                hintText: 'https://…/ical/…'),
            keyboardType: TextInputType.url,
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: 8),
          Text(
            _personal
                ? 'Google Agenda: op een computer ⚙ Instellingen → kies de agenda → '
                    '"Agenda integreren" → "Geheim adres in iCal-indeling". '
                    'Deel die link met niemand.'
                : 'Rentman: bij je profiel of agenda, onder agenda-synchronisatie. '
                    'Per opdrachtgever voeg je een eigen agenda toe.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Annuleren')),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Opslaan')),
      ],
    );
  }
}

class CalendarsScreen extends StatelessWidget {
  const CalendarsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda\'s'), actions: [
        StoreBuilder(
            builder: (_) => IconButton(
                tooltip: 'Alles verversen',
                onPressed: store.syncing ? null : store.syncAll,
                icon: const Icon(Icons.refresh))),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddCalendar(context),
        icon: const Icon(Icons.add),
        label: const Text('Agenda toevoegen'),
      ),
      body: StoreBuilder(builder: (context) {
        final cals = store.calendars;
        if (cals.isEmpty) {
          return const Center(
            child: EmptyHint(
              icon: Icons.event_available_outlined,
              title: 'Koppel je eerste agenda',
              body:
                  'Plak de iCal-link die je als crewlid van een opdrachtgever krijgt. '
                  'Je kunt er zoveel toevoegen als je wilt.',
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: cals.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final c = cals[i];
            final count = store.jobs.where((j) => j.calId == c.id).length;
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 4),
                leading: Icon(
                    c.error == null ? Icons.event_available : Icons.error_outline,
                    color: c.error == null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error),
                title: Text(c.name,
                    style: TextStyle(color: c.enabled ? null : muted)),
                subtitle: Text(c.personal && c.enabled && c.error == null
                    ? 'Persoonlijk · $count afspraken · telt niet mee voor facturen'
                    : !c.enabled
                    ? 'Uit: verborgen in je planning; afgelopen klussen blijven in Te verwerken en het overzicht'
                    : c.error ??
                    (c.lastSync == null
                        ? 'Nog niet gesynchroniseerd'
                        : '$count klussen · bijgewerkt ${dateShort(c.lastSync!)} ${hm(c.lastSync!)}')),
                isThreeLine: c.error != null || !c.enabled,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(
                    value: c.enabled,
                    onChanged: (v) => store.setCalendarEnabled(c, v),
                  ),
                  PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'sync') store.syncCalendar(c);
                    if (v == 'edit') showAddCalendar(context, edit: c);
                    if (v == 'del' &&
                        await confirm(context, 'Agenda verwijderen?',
                            'De klussen uit "${c.name}" verdwijnen uit de app. Je notities en foto\'s blijven bewaard.')) {
                      store.removeCalendar(c.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'sync', child: Text('Nu verversen')),
                    PopupMenuItem(value: 'edit', child: Text('Wijzigen')),
                    PopupMenuItem(value: 'del', child: Text('Verwijderen')),
                  ],
                ),
                ]),
              ),
            );
          },
        );
      }),
    );
  }
}
