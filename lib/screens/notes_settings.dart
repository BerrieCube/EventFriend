import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keep_import.dart';
import '../store.dart';
import 'common.dart';
import 'notes.dart';

const _palette = [
  0xFFEF9F27, // amber
  0xFF5B9BE6, // blauw
  0xFF4CAF7A, // groen
  0xFFB07CE8, // paars
  0xFFE57399, // roze
  0xFF3DBFB8, // teal
  0xFFE5654B, // rood
  0xFFB8B6AF, // grijs
];

/// Instellingen voor Notities: omgevingen, pincode Privé en Keep-import.
class NotesSettingsScreen extends StatelessWidget {
  const NotesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notities')),
      body: StoreBuilder(builder: (context) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
                'Je hebt twee gescheiden omgevingen voor notities, elk met eigen '
                'labels, archief en prullenbak. Klusnotities staan altijd in de eerste.',
                style: TextStyle(color: muted)),
            const SectionTitle('Omgevingen'),
            for (final s in Store.spaces)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: spaceColor(s),
                    ),
                    title: Text(store.spaceName(s)),
                    subtitle: Text(s == 'work'
                        ? 'Ook voor notities bij klussen'
                        : 'Alleen losse notities'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editSpace(context, s),
                  ),
                ),
              ),
            const SectionTitle('Beveiliging'),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.lock_outline),
                title: Text('Pincode voor ${store.spaceName('private')}'),
                subtitle: const Text(
                    'Alleen op dit apparaat. Houdt meekijkers tegen; '
                    'de notities zelf worden niet versleuteld.'),
                value: store.privatePin != null,
                onChanged: (v) async {
                  if (v) {
                    final pin = await _askNewPin(context);
                    if (pin != null) {
                      await store.setPrivatePin(pin);
                      privateUnlocked = true;
                    }
                  } else {
                    if (await unlockPrivate(context)) {
                      await store.setPrivatePin(null);
                    }
                  }
                },
              ),
            ),
            const SectionTitle('Google Keep'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Notities importeren uit Google Keep'),
                subtitle: const Text(
                    'Titels, tekst, checklists, labels, vastgezet, archief en afbeeldingen'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => importKeepFlow(context),
              ),
            ),
          ],
        );
      }),
    );
  }
}

Future<void> _editSpace(BuildContext context, String s) async {
  final name = TextEditingController(text: store.spaceName(s));
  var color = store.spaceColor(s);
  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      return AlertDialog(
        title: const Text('Omgeving'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Naam'),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final p in _palette)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setS(() => color = p),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(p),
                  child: color == p
                      ? const Icon(Icons.check, size: 18, color: Colors.black)
                      : null,
                ),
              ),
          ]),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () async {
              final n = name.text.trim();
              if (n.isNotEmpty) await store.setPref('space_${s}_name', n);
              await store.setPref('space_${s}_color', color);
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('Opslaan'),
          ),
        ],
      );
    }),
  );
}

Future<String?> _askNewPin(BuildContext context) {
  final a = TextEditingController(), b = TextEditingController();
  String? err;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      InputDecoration dec(String l) => InputDecoration(labelText: l);
      return AlertDialog(
        title: const Text('Pincode instellen'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: a,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: dec('Pincode (minstens 4 cijfers)')),
          const SizedBox(height: 8),
          TextField(
              controller: b,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: dec('Herhaal pincode')),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(err!,
                  style: TextStyle(color: Theme.of(c).colorScheme.error)),
            ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () {
              if (a.text.length < 4) {
                setS(() => err = 'Gebruik minstens 4 cijfers.');
              } else if (a.text != b.text) {
                setS(() => err = 'De pincodes zijn niet gelijk.');
              } else {
                Navigator.pop(c, a.text);
              }
            },
            child: const Text('Instellen'),
          ),
        ],
      );
    }),
  );
}

/// Uitleg, bestand kiezen, omgeving kiezen en importeren.
Future<void> importKeepFlow(BuildContext context) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Importeren uit Google Keep'),
      content: const SingleChildScrollView(
        child: Text(
          '1. Ga op een computer naar takeout.google.com en log in met het '
          'Google-account van die Keep.\n'
          '2. Klik op "Selectie van alles opheffen" en vink alleen "Keep" aan.\n'
          '3. Kies "Volgende stap" → "Export maken" en download de .zip.\n'
          '4. Kies hierna dat .zip-bestand (of losse .json-bestanden uit de map Keep).\n\n'
          'Notities in de Keep-prullenbak worden overgeslagen. Importeer je '
          'dezelfde export nog een keer, dan worden notities bijgewerkt en niet verdubbeld.',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuleren')),
        FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Bestand kiezen')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['zip', 'json'],
  );
  if (picked.isEmpty || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  KeepImportResult result;
  try {
    final files = [
      for (final f in picked) (f.name, await f.xFile.readAsBytes())
    ];
    result = parseKeep(files);
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('Kon het bestand niet lezen: $e')));
    return;
  }
  if (result.notes.isEmpty) {
    messenger.showSnackBar(const SnackBar(
        content: Text(
            'Geen Keep-notities gevonden. Kies de .zip uit Google Takeout.')));
    return;
  }
  if (!context.mounted) return;

  final space = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('${result.notes.length} notities gevonden'),
      content: Text([
        'In welke omgeving wil je ze zetten?',
        if (result.skippedTrashed > 0)
          '${result.skippedTrashed} notitie(s) uit de Keep-prullenbak worden overgeslagen.',
      ].join('\n\n')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c), child: const Text('Annuleren')),
        for (final s in Store.spaces)
          FilledButton.tonal(
              onPressed: () => Navigator.pop(c, s),
              child: Text(store.spaceName(s))),
      ],
    ),
  );
  if (space == null || !context.mounted) return;

  if (!context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox(
            width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 16),
        Expanded(child: Text('Notities importeren…')),
      ]),
    ),
  );
  final (n, p) = await importKeep(result, space: space);
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  messenger.showSnackBar(SnackBar(
      content: Text(
          '$n notities${p > 0 ? ' en $p afbeeldingen' : ''} geïmporteerd in ${store.spaceName(space)}')));
}
