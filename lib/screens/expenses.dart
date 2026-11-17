import 'package:flutter/material.dart';

import '../format.dart';
import '../route.dart';
import '../store.dart';
import 'common.dart';

/// Kaartje op de klus-pagina met kilometers en onkosten.
class ExpensesCard extends StatelessWidget {
  final Job job;
  const ExpensesCard({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    final m = store.meta(job.key);
    final km = store.kmFor(job);
    final lines = [
      if (km > 0) '${nf(km, 0)} km',
      if (m.parking > 0) 'Parkeren ${euro(m.parking)}',
      if (m.costs > 0)
        '${m.costNote.isEmpty ? 'Overige kosten' : m.costNote} ${euro(m.costs)}',
    ];
    return Card(
      child: ListTile(
        leading: const Icon(Icons.directions_car_outlined),
        title: Text(lines.isEmpty ? 'Nog niets ingevuld' : lines.join(' · ')),
        subtitle: Text(m.invoiced != null
            ? 'Gefactureerd op ${dateShort(m.invoiced!)}'
            : 'Komt mee in het overzicht per opdrachtgever'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => editExpenses(context, job),
      ),
    );
  }
}

Future<void> editExpenses(BuildContext context, Job job) async {
  final m = store.meta(job.key);
  final km = TextEditingController(text: m.km == 0 ? '' : nf(m.km, 0));
  final parking =
      TextEditingController(text: m.parking == 0 ? '' : nf(m.parking, 2));
  final costs = TextEditingController(text: m.costs == 0 ? '' : nf(m.costs, 2));
  final note = TextEditingController(text: m.costNote);
  var invoiced = m.invoiced != null;
  var busy = false;
  String? msg;

  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      Future<void> calc() async {
        var home = store.homeAddress;
        if (home.isEmpty) {
          home = await askHomeAddress(c) ?? '';
          if (home.isEmpty) return;
        }
        if (job.location.isEmpty) {
          setS(() => msg = 'Deze klus heeft geen locatie.');
          return;
        }
        setS(() {
          busy = true;
          msg = null;
        });
        try {
          final one = await roadDistanceKm(home, job.location);
          km.text = nf(one * 2, 0);
          msg = 'Heen ${nf(one, 1)} km + terug = ${nf(one * 2, 0)} km';
        } catch (e) {
          msg = e.toString().replaceFirst('Exception: ', '');
        }
        setS(() => busy = false);
      }

      return AlertDialog(
        title: const Text('Kilometers & onkosten'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: km,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Kilometers (heen en terug)', suffixText: 'km'),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: busy ? null : calc,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.route, size: 18),
                label: const Text('Berekenen vanaf thuis'),
              ),
            ),
            if (msg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(msg!, style: const TextStyle(color: muted)),
              ),
            TextField(
              controller: parking,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Parkeren', prefixText: '€ '),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: costs,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Overige kosten', prefixText: '€ '),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                  labelText: 'Omschrijving overige kosten',
                  hintText: 'bijv. tol, OV, maaltijd'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gefactureerd'),
              value: invoiced,
              onChanged: (v) => setS(() => invoiced = v),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () {
              m.km = parseNum(km.text) ?? 0;
              m.parking = parseNum(parking.text) ?? 0;
              m.costs = parseNum(costs.text) ?? 0;
              m.costNote = note.text.trim();
              if (invoiced != (m.invoiced != null)) {
                m.invoiced = invoiced ? DateTime.now() : null;
              }
              store.saveMeta(m);
              Navigator.pop(c);
            },
            child: const Text('Opslaan'),
          ),
        ],
      );
    }),
  );
}

/// Vraagt het thuisadres en slaat het op. Geeft het adres terug (of null).
Future<String?> askHomeAddress(BuildContext context) async {
  final ctrl = TextEditingController(text: store.homeAddress);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Thuisadres'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Straat, huisnummer, plaats',
              hintText: 'bijv. Dorpsstraat 1, Utrecht'),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        const SizedBox(height: 10),
        const Text(
            'Wordt gebruikt om kilometers te berekenen. Bij het berekenen gaan '
            'je thuisadres en de locatie van de klus naar OpenStreetMap.',
            style: TextStyle(color: muted, fontSize: 12)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c), child: const Text('Annuleren')),
        FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Opslaan')),
      ],
    ),
  );
  if (r == null) return null;
  await store.setPref('home', r);
  return r;
}
