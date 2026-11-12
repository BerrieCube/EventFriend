import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../format.dart';
import '../pdf_export.dart';
import '../store.dart';
import 'common.dart';
import 'jobs.dart';
import 'notes.dart';

void openJob(BuildContext context, String key) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => JobDetailScreen(jobKey: key)));
}

class JobDetailScreen extends StatelessWidget {
  final String jobKey;
  const JobDetailScreen({super.key, required this.jobKey});

  Future<void> _addPhoto(BuildContext context, ImageSource source) async {
    try {
      final x = await ImagePicker()
          .pickImage(source: source, maxWidth: 1800, imageQuality: 80);
      if (x == null) return;
      await store.addPhoto(jobKey, await x.readAsBytes());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Foto toevoegen mislukt: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context) {
      final job = store.job(jobKey);
      if (job == null) {
        return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Deze klus bestaat niet meer.')));
      }
      final cal = store.calendar(job.calId);
      final notes = store.notesFor(job.key);
      final photos = store.photosFor(job.key);
      final phones = job.phoneNumbers;

      return Scaffold(
        appBar: AppBar(
          title: const Text('Klus'),
          actions: [
            if (job.isManual)
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') editManualJob(context, job: job);
                  if (v == 'del' &&
                      await confirm(context, 'Klus verwijderen?',
                          'De klus wordt verwijderd. Notities en foto\'s blijven in de app.')) {
                    await store.deleteJob(job.key);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Wijzigen')),
                  PopupMenuItem(value: 'del', child: Text('Verwijderen')),
                ],
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: () => exportJobPdf(context, job),
                icon: const Icon(Icons.ios_share),
                label: const Text('Exporteer notities en foto\'s (PDF)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(job.title,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                '${dateLong(job.start)} · ${hm(job.start)}–${hm(job.end)}',
                style: const TextStyle(color: muted)),
            Text(cal?.name ?? (job.isManual ? 'Eigen klus' : ''),
                style: const TextStyle(color: muted)),
            if (job.location.isNotEmpty || phones.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (job.location.isNotEmpty)
                  ActionChip(
                      avatar: const Icon(Icons.navigation_outlined, size: 18),
                      label: Text(job.location),
                      onPressed: () => openRoute(job.location)),
                for (final p in phones)
                  ActionChip(
                      avatar: const Icon(Icons.phone_outlined, size: 18),
                      label: Text(p),
                      onPressed: () => callNumber(p)),
              ]),
            ],
            if (job.description.isNotEmpty) ...[
              const SectionTitle('Info uit Rentman'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(job.description),
                ),
              ),
            ],
            SectionTitle('Notities',
                trailing: IconButton(
                    tooltip: 'Notitie toevoegen',
                    icon: const Icon(Icons.add),
                    onPressed: () => editNote(context, job: job))),
            if (notes.isEmpty)
              const Text('Nog geen notities.', style: TextStyle(color: muted)),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    title: Text(n.text),
                    subtitle: Text('${dateShort(n.created)} ${hm(n.created)}'),
                    onTap: () => editNote(context, note: n, job: job),
                  ),
                ),
              ),
            SectionTitle('Foto\'s',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Foto maken',
                      icon: const Icon(Icons.photo_camera_outlined),
                      onPressed: () => _addPhoto(context, ImageSource.camera)),
                  IconButton(
                      tooltip: 'Uit galerij',
                      icon: const Icon(Icons.photo_library_outlined),
                      onPressed: () => _addPhoto(context, ImageSource.gallery)),
                ])),
            if (photos.isEmpty)
              const Text('Nog geen foto\'s.', style: TextStyle(color: muted)),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final p in photos)
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _PhotoView(photo: p))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(p.bytes, fit: BoxFit.cover),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _PhotoView extends StatefulWidget {
  final Photo photo;
  const _PhotoView({required this.photo});

  @override
  State<_PhotoView> createState() => _PhotoViewState();
}

class _PhotoViewState extends State<_PhotoView> {
  late final _caption = TextEditingController(text: widget.photo.caption);

  @override
  void dispose() {
    widget.photo.caption = _caption.text.trim();
    store.savePhoto(widget.photo);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(
          tooltip: 'Verwijderen',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (await confirm(context, 'Foto verwijderen?',
                'De foto wordt uit de app verwijderd.')) {
              await store.deletePhoto(widget.photo.id);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
      ]),
      body: Column(children: [
        Expanded(
            child: InteractiveViewer(
                child: Center(child: Image.memory(widget.photo.bytes)))),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _caption,
            decoration: const InputDecoration(
                labelText: 'Bijschrift (komt mee in de PDF)'),
          ),
        ),
      ]),
    );
  }
}
