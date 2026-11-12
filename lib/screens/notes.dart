import 'package:flutter/material.dart';

import '../format.dart';
import '../store.dart';
import 'common.dart';
import 'job_detail.dart';

/// Notitie maken of wijzigen. Met [job] wordt hij aan die klus gekoppeld.
Future<void> editNote(BuildContext context, {Note? note, Job? job}) {
  return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _NoteEditor(note: note, job: job)));
}

class _NoteEditor extends StatefulWidget {
  final Note? note;
  final Job? job;
  const _NoteEditor({this.note, this.job});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _text = TextEditingController(text: widget.note?.text ?? '');
  late String? _jobKey = widget.note?.jobKey ?? widget.job?.key;

  Future<void> _save() async {
    final t = _text.text.trim();
    if (t.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final now = DateTime.now();
    final n = widget.note ??
        Note(id: newId(), text: '', created: now, updated: now);
    n.text = t;
    n.jobKey = _jobKey;
    n.jobTitle = store.job(_jobKey)?.title;
    await store.saveNote(n);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Keuzelijst: klussen van 30 dagen terug tot 60 dagen vooruit.
    final now = DateTime.now();
    final jobs = store.jobs
        .where((j) =>
            j.start.isAfter(now.subtract(const Duration(days: 30))) &&
            j.start.isBefore(now.add(const Duration(days: 60))))
        .toList();
    final current = store.job(_jobKey);
    if (current != null && !jobs.any((j) => j.key == current.key)) {
      jobs.insert(0, current);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.note == null ? 'Nieuwe notitie' : 'Notitie'),
          actions: [
            if (widget.note != null)
              IconButton(
                tooltip: 'Verwijderen',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, 'Notitie verwijderen?',
                      'Dit kan niet ongedaan worden gemaakt.')) {
                    await store.deleteNote(widget.note!.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            IconButton(
                tooltip: 'Opslaan',
                icon: const Icon(Icons.check),
                onPressed: _save),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            DropdownButtonFormField<String?>(
              initialValue: _jobKey,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Klus'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Losse notitie (geen klus)')),
                for (final j in jobs)
                  DropdownMenuItem(
                      value: j.key,
                      child: Text('${dateShort(j.start)} · ${j.title}',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _jobKey = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _text,
                autofocus: widget.note == null,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'Patch, IP-adressen, afspraken, spare parts…'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Notities'), actions: const [SettingsAction()]),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nieuwe notitie',
        onPressed: () => editNote(context),
        child: const Icon(Icons.add),
      ),
      body: StoreBuilder(builder: (context) {
        final q = _q.toLowerCase();
        final notes = store.notes
            .where((n) =>
                q.isEmpty ||
                n.text.toLowerCase().contains(q) ||
                (n.jobTitle ?? '').toLowerCase().contains(q))
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Zoeken'),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 12),
            if (notes.isEmpty)
              const EmptyHint(
                  icon: Icons.sticky_note_2_outlined,
                  title: 'Nog geen notities',
                  body:
                      'Maak een losse notitie, of koppel hem aan een klus zodat je hem kunt exporteren.'),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    title: Text(n.text,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      '${dateShort(n.updated)} ${hm(n.updated)}',
                      if (n.jobTitle != null) n.jobTitle!,
                    ].join(' · ')),
                    trailing: n.jobKey != null && store.job(n.jobKey) != null
                        ? IconButton(
                            tooltip: 'Naar klus',
                            icon: const Icon(Icons.event_note_outlined),
                            onPressed: () => openJob(context, n.jobKey!))
                        : null,
                    onTap: () => editNote(context, note: n),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}
