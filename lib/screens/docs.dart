import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../platform/open_doc.dart';
import '../store.dart';
import 'common.dart';
import 'viewer.dart';

String fileSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${nf(b / 1024, 0)} kB';
  return '${nf(b / 1024 / 1024, 1)} MB';
}

/// Bestand kiezen en toevoegen (aan een klus of aan de bibliotheek).
Future<void> pickAndAddFile(BuildContext context, {Job? job}) async {
  final r = await FilePicker.pickFiles(
    type: job == null ? FileType.any : FileType.custom,
    allowedExtensions: job == null ? null : ['pdf', 'jpg', 'jpeg', 'png'],
  );
  var skipped = 0;
  for (final f in r) {
    final bytes = await f.xFile.readAsBytes();
    if (bytes.length > 50 * 1024 * 1024) {
      skipped++;
      continue;
    }
    await store.addFile(f.name, bytes, job: job);
  }
  if (skipped > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$skipped bestand(en) overgeslagen (max. 50 MB).')));
  }
}

Future<void> addLinkDialog(BuildContext context, {Doc? edit}) async {
  final name = TextEditingController(text: edit?.name ?? '');
  final url = TextEditingController(text: edit?.url ?? '');
  String? error;
  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(edit == null ? 'Link toevoegen' : 'Link wijzigen'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(
                  labelText: 'Naam', hintText: 'Handleiding Barco E2')),
          const SizedBox(height: 8),
          TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Link', hintText: 'https://…')),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!,
                  style: TextStyle(color: Theme.of(c).colorScheme.error)),
            ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || url.text.trim().isEmpty) {
                setS(() => error = 'Vul een naam en een link in.');
                return;
              }
              if (edit == null) {
                store.addLink(name.text.trim(), url.text.trim());
              } else {
                edit.name = name.text.trim();
                var u = url.text.trim();
                if (!u.contains('://')) u = 'https://$u';
                edit.url = u;
                store.saveDoc(edit);
              }
              Navigator.pop(c);
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _rename(BuildContext context, Doc d) async {
  final c = TextEditingController(text: d.name);
  final r = await showDialog<String>(
    context: context,
    builder: (dc) => AlertDialog(
      title: const Text('Naam wijzigen'),
      content: TextField(controller: c, autofocus: true),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dc), child: const Text('Annuleren')),
        FilledButton(
            onPressed: () => Navigator.pop(dc, c.text.trim()),
            child: const Text('Opslaan')),
      ],
    ),
  );
  if (r != null && r.isNotEmpty) {
    d.name = r;
    await store.saveDoc(d);
  }
}

Future<void> openDoc(BuildContext context, Doc d,
    {List<Doc> siblings = const []}) async {
  if (d.isLink) {
    await launchUrl(Uri.parse(d.url!), mode: LaunchMode.externalApplication);
    return;
  }
  final bytes = d.bytes;
  if (bytes == null) return;
  if (viewKindOf(d) != ViewKind.none) {
    openViewer(context, d, siblings: siblings);
    return;
  }
  final err = await openBytes(d.name, d.mime, bytes);
  if (err != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Geen app gevonden om dit te openen ($err).')));
  }
}

Future<void> shareDoc(Doc d) async {
  if (d.isLink) {
    await SharePlus.instance.share(ShareParams(text: '${d.name}\n${d.url}'));
    return;
  }
  final bytes = d.bytes;
  if (bytes == null) return;
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: d.mime, name: d.name)],
    fileNameOverrides: [d.name],
  ));
}

class DocTile extends StatelessWidget {
  final Doc doc;
  final List<Doc> siblings; // voor doorvegen tussen afbeeldingen
  const DocTile({super.key, required this.doc, this.siblings = const []});

  IconData get _icon {
    if (doc.isLink) return Icons.link;
    if (doc.isPdf) return Icons.picture_as_pdf_outlined;
    if (doc.mime.startsWith('image/')) return Icons.image_outlined;
    return Icons.description_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final d = doc;
    final sub = <String>[
      if (d.isLink) d.url ?? '' else fileSize(d.size),
      if (d.deleteAfter != null) 'wordt verwijderd op ${dateShort(d.deleteAfter!)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Icon(_icon, color: Theme.of(context).colorScheme.primary),
          title: Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => openDoc(context, d, siblings: siblings),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'share') shareDoc(d);
              if (v == 'external' && d.bytes != null) {
                openBytes(d.name, d.mime, d.bytes!);
              }
              if (v == 'rename') {
                d.isLink ? addLinkDialog(context, edit: d) : _rename(context, d);
              }
              if (v == 'del' &&
                  await confirm(context, 'Verwijderen?',
                      '"${d.name}" wordt van al je apparaten verwijderd.')) {
                store.deleteDoc(d.id);
              }
            },
            itemBuilder: (_) => [
              if (!d.isLink)
                const PopupMenuItem(
                    value: 'external', child: Text('Openen in andere app')),
              const PopupMenuItem(value: 'share', child: Text('Delen')),
              const PopupMenuItem(value: 'rename', child: Text('Wijzigen')),
              const PopupMenuItem(value: 'del', child: Text('Verwijderen')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tools → Handige documenten & links.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documenten & links')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          showDragHandle: true,
          builder: (c) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Document toevoegen'),
                subtitle: const Text('PDF, afbeelding, Word, enz.'),
                onTap: () {
                  Navigator.pop(c);
                  pickAndAddFile(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_link),
                title: const Text('Link toevoegen'),
                onTap: () {
                  Navigator.pop(c);
                  addLinkDialog(context);
                },
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Toevoegen'),
      ),
      body: StoreBuilder(builder: (context) {
        final docs = store.libraryDocs;
        final files = docs.where((d) => !d.isLink).toList();
        final links = docs.where((d) => d.isLink).toList();
        if (docs.isEmpty) {
          return const Center(
            child: EmptyHint(
              icon: Icons.folder_open,
              title: 'Je naslagwerk op één plek',
              body:
                  'Bewaar handleidingen, specsheets, patchlijsten en handige links. '
                  'Ze staan ook offline op je telefoon.',
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            if (files.isNotEmpty) const SectionTitle('Documenten'),
            for (final d in files) DocTile(doc: d, siblings: files),
            if (links.isNotEmpty) const SectionTitle('Links'),
            for (final d in links) DocTile(doc: d),
          ],
        );
      }),
    );
  }
}
