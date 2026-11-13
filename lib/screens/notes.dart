import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../device.dart';
import '../format.dart';
import '../note_text.dart';
import '../store.dart';
import 'common.dart';
import 'job_detail.dart';

/// Notitie maken of wijzigen. Met [job] wordt hij aan die klus gekoppeld.
Future<void> editNote(BuildContext context, {Note? note, Job? job, String? tag}) {
  return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _NoteEditor(note: note, job: job, tag: tag)));
}

// ============================================================ Editor

class _NoteEditor extends StatefulWidget {
  final Note? note;
  final Job? job;
  final String? tag;
  const _NoteEditor({this.note, this.job, this.tag});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final QuillController _quill;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late String? _jobKey = widget.note?.jobKey ?? widget.job?.key;
  late bool _lock = widget.note?.lockscreen ?? false;
  late bool _widget = widget.note?.widget ?? false;
  late bool _pinned = widget.note?.pinned ?? false;
  late final List<String> _tags = [
    ...?widget.note?.tags,
    if (widget.note == null && widget.tag != null) widget.tag!,
  ];
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    final delta = n?.content ?? (n == null ? null : plainToDelta(n.text));
    Document doc;
    try {
      doc = delta == null
          ? Document()
          : Document.fromJson(jsonDecode(delta) as List);
    } catch (_) {
      doc = Document()..insert(0, n?.text ?? '');
    }
    _quill = QuillController(
        document: doc, selection: const TextSelection.collapsed(offset: 0));
  }

  @override
  void dispose() {
    _quill.dispose();
    _focus.dispose();
    _scroll.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saved) return;
    _saved = true;
    final content = jsonEncode(_quill.document.toDelta().toJson());
    final plain = deltaToPlain(content);
    final title = _title.text.trim();
    if (plain.trim().isEmpty && title.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final now = DateTime.now();
    final n =
        widget.note ?? Note(id: newId(), text: '', created: now, updated: now);
    if (widget.note == null) {
      // Nieuwe notitie bovenaan.
      final all = store.notes;
      n.order = all.isEmpty
          ? 0
          : all.map((x) => x.order).reduce((a, b) => a < b ? a : b) - 1;
    }
    n.title = title;
    n.content = content;
    n.text = plain;
    n.jobKey = _jobKey;
    n.jobTitle = store.job(_jobKey)?.title;
    n.lockscreen = _lock;
    n.pinned = _pinned;
    n.tags = List.of(_tags);
    if (_widget && !n.widget) {
      for (final o in store.notes.where((o) => o.widget && o.id != n.id)) {
        o.widget = false;
        await store.saveNote(o, touch: false);
      }
    }
    n.widget = _widget;
    await store.saveNote(n);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _more() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, setS) {
        void both(VoidCallback f) {
          setState(f);
          setS(() {});
        }

        final now = DateTime.now();
        final jobs = store.jobs
            .where((j) =>
                j.start.isAfter(now.subtract(const Duration(days: 30))) &&
                j.start.isBefore(now.add(const Duration(days: 60))))
            .toList();
        final cur = store.job(_jobKey);
        if (cur != null && !jobs.any((j) => j.key == cur.key)) {
          jobs.insert(0, cur);
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String?>(
                initialValue: _jobKey,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Klus'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Geen klus')),
                  for (final j in jobs)
                    DropdownMenuItem(
                        value: j.key,
                        child: Text(
                            '${dateShort(j.start)} · ${store.clientName(j)} · ${j.title}',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => both(() => _jobKey = v),
              ),
              if (device.supported) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Op vergrendelscherm'),
                  subtitle: const Text('Als vaste melding, tot je hem uitzet'),
                  value: _lock,
                  onChanged: (v) async {
                    if (v && !await device.requestPermission()) return;
                    both(() => _lock = v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Op widget'),
                  subtitle:
                      const Text('Toont deze notitie in de notitie-widget'),
                  value: _widget,
                  onChanged: (v) => both(() => _widget = v),
                ),
              ],
              if (widget.note != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Notitie verwijderen'),
                  onTap: () async {
                    Navigator.pop(c);
                    if (await confirm(context, 'Notitie verwijderen?',
                        'Dit kan niet ongedaan worden gemaakt.')) {
                      _saved = true;
                      await store.deleteNote(widget.note!.id);
                      if (mounted) Navigator.pop(context);
                    }
                  },
                ),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _editTags() async {
    final r = await pickTags(context, selected: _tags.toSet());
    if (r != null) {
      setState(() => _tags
        ..clear()
        ..addAll(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = store.job(_jobKey);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: _pinned ? 'Losmaken' : 'Vastzetten',
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () => setState(() => _pinned = !_pinned),
            ),
            IconButton(
                tooltip: 'Tags',
                icon: const Icon(Icons.sell_outlined),
                onPressed: _editTags),
            IconButton(
                tooltip: 'Meer',
                icon: const Icon(Icons.more_vert),
                onPressed: _more),
            IconButton(
                tooltip: 'Opslaan',
                icon: const Icon(Icons.check),
                onPressed: _save),
          ],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'Titel (optioneel)',
                filled: false,
                border: InputBorder.none,
              ),
            ),
          ),
          if (job != null || _tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  if (job != null)
                    Chip(
                      avatar: const Icon(Icons.event_note, size: 16),
                      label: Text('${store.clientName(job)} · ${job.title}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  for (final t in _tags)
                    InputChip(
                      label: Text('#$t'),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => setState(() => _tags.remove(t)),
                    ),
                ]),
              ),
            ),
          QuillSimpleToolbar(
            controller: _quill,
            config: const QuillSimpleToolbarConfig(
              multiRowsDisplay: false,
              showDividers: false,
              showFontFamily: false,
              showFontSize: false,
              showSmallButton: false,
              showStrikeThrough: false,
              showInlineCode: false,
              showColorButton: false,
              showBackgroundColorButton: false,
              showClearFormat: false,
              showAlignmentButtons: false,
              showHeaderStyle: false,
              showCodeBlock: false,
              showQuote: false,
              showIndent: false,
              showLink: false,
              showSearchButton: false,
              showSubscript: false,
              showSuperscript: false,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: QuillEditor(
                controller: _quill,
                focusNode: _focus,
                scrollController: _scroll,
                config: QuillEditorConfig(
                  placeholder: 'Patch, IP-adressen, afspraken, spare parts…',
                  autoFocus: widget.note == null,
                  expands: true,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ============================================================ Tags kiezen

/// Laat tags kiezen en nieuwe aanmaken. Geeft null bij annuleren.
Future<Set<String>?> pickTags(BuildContext context,
    {Set<String> selected = const {}}) {
  final sel = {...selected};
  final ctrl = TextEditingController();
  return showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      final tags = {...store.allTags, ...sel}.toList()..sort();
      void add() {
        final t = ctrl.text.trim().replaceAll('#', '');
        if (t.isEmpty) return;
        store.addTag(t);
        setS(() {
          sel.add(t);
          ctrl.clear();
        });
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 16 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Tags',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                    hintText: 'Nieuwe tag, bijv. LED of Barco', isDense: true),
                onSubmitted: (_) => add(),
              ),
            ),
            IconButton(onPressed: add, icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in tags)
              FilterChip(
                label: Text('#$t'),
                selected: sel.contains(t),
                onSelected: (v) => setS(() => v ? sel.add(t) : sel.remove(t)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Annuleren')),
            FilledButton(
                onPressed: () => Navigator.pop(c, sel),
                child: const Text('Klaar')),
          ]),
        ]),
      );
    }),
  );
}

// ============================================================ Overzicht

/// Filters bovenaan de notitielijst: 'all', 'loose', 'jobs', 'past' of '#tag'.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String _q = '';
  String _filter = 'all';
  final _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  bool _matches(Note n) {
    final now = DateTime.now();
    final j = store.job(n.jobKey);
    final ok = switch (_filter) {
      'all' => true,
      'loose' => n.jobKey == null,
      'jobs' => j != null && !j.end.isBefore(now),
      'past' => j != null && j.end.isBefore(now),
      _ => n.tags.contains(_filter.substring(1)),
    };
    if (!ok) return false;
    final q = _q.toLowerCase();
    return q.isEmpty ||
        n.title.toLowerCase().contains(q) ||
        n.text.toLowerCase().contains(q) ||
        (n.jobTitle ?? '').toLowerCase().contains(q) ||
        n.tags.any((t) => t.toLowerCase().contains(q));
  }

  Future<void> _deleteSelected() async {
    final n = _selected.length;
    if (!await confirm(context, '$n notitie(s) verwijderen?',
        'Dit kan niet ongedaan worden gemaakt.')) {
      return;
    }
    for (final id in _selected.toList()) {
      await store.deleteNote(id);
    }
    setState(_selected.clear);
  }

  Future<void> _pinSelected() async {
    final notes = store.notes.where((n) => _selected.contains(n.id)).toList();
    final pin = notes.any((n) => !n.pinned);
    for (final n in notes) {
      n.pinned = pin;
      await store.saveNote(n, touch: false);
    }
    setState(_selected.clear);
  }

  Future<void> _tagSelected() async {
    final notes = store.notes.where((n) => _selected.contains(n.id)).toList();
    final common = notes.isEmpty
        ? <String>{}
        : notes.map((n) => n.tags.toSet()).reduce((a, b) => a.intersection(b));
    final r = await pickTags(context, selected: common);
    if (r == null) return;
    final removed = common.difference(r);
    for (final n in notes) {
      n.tags = {...n.tags.where((t) => !removed.contains(t)), ...r}.toList();
      await store.saveNote(n, touch: false);
    }
    setState(_selected.clear);
  }

  /// Gesleepte notitie(s) op een tag losgelaten.
  Future<void> _dropOnTag(String id, String tag) async {
    final ids = {..._selected, id};
    for (final n in store.notes.where((n) => ids.contains(n.id))) {
      if (!n.tags.contains(tag)) {
        n.tags.add(tag);
        await store.saveNote(n, touch: false);
      }
    }
    setState(_selected.clear);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${ids.length} notitie(s) getagd met #$tag')));
    }
  }

  Future<void> _reorder(List<Note> shown, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    if (newIndex == oldIndex) return;
    final moved = shown.removeAt(oldIndex);
    shown.insert(newIndex, moved);
    final before = newIndex > 0 ? shown[newIndex - 1] : null;
    final after = newIndex < shown.length - 1 ? shown[newIndex + 1] : null;
    if (before == null && after == null) return;
    moved.order = before == null
        ? after!.order - 1
        : after == null
            ? before.order + 1
            : (before.order + after.order) / 2;
    // Slepen tussen vastgezette notities zet hem vast, en andersom.
    moved.pinned = before?.pinned ?? after!.pinned;
    await store.saveNote(moved, touch: false);
  }

  Widget _chip(String label, String f, {IconData? icon}) {
    final chip = ChoiceChip(
      avatar: icon == null ? null : Icon(icon, size: 16),
      label: Text(label),
      selected: _filter == f,
      onSelected: (_) => setState(() => _filter = f),
    );
    if (!f.startsWith('#')) return chip;
    final tag = f.substring(1);
    // Notities op een tag slepen om ze die tag te geven.
    return DragTarget<String>(
      onAcceptWithDetails: (d) => _dropOnTag(d.data, tag),
      builder: (c, cand, _) => AnimatedScale(
        scale: cand.isEmpty ? 1 : 1.15,
        duration: const Duration(milliseconds: 120),
        child: GestureDetector(
          onLongPress: () async {
            if (await confirm(context, 'Tag #$tag verwijderen?',
                'De tag wordt van alle notities gehaald. De notities zelf blijven bestaan.')) {
              await store.removeTag(tag);
              if (_filter == f) setState(() => _filter = 'all');
            }
          },
          child: chip,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context) {
      final shown = store.notes.where(_matches).toList();
      final tags = store.allTags;
      return Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                    tooltip: 'Klaar',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_selected.clear)),
                title: Text('${_selected.length} geselecteerd'),
                actions: [
                  IconButton(
                      tooltip: 'Alles selecteren',
                      icon: const Icon(Icons.select_all),
                      onPressed: () => setState(
                          () => _selected.addAll(shown.map((n) => n.id)))),
                  IconButton(
                      tooltip: 'Vastzetten / losmaken',
                      icon: const Icon(Icons.push_pin_outlined),
                      onPressed: _pinSelected),
                  IconButton(
                      tooltip: 'Tags',
                      icon: const Icon(Icons.sell_outlined),
                      onPressed: _tagSelected),
                  IconButton(
                      tooltip: 'Verwijderen',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _deleteSelected),
                ],
              )
            : AppBar(title: const Text('Notities'), actions: [
                IconButton(
                    tooltip: 'Selecteren',
                    icon: const Icon(Icons.checklist),
                    onPressed: shown.isEmpty
                        ? null
                        : () => setState(() => _selected.add(shown.first.id))),
                const SettingsAction(),
              ]),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton(
                tooltip: 'Nieuwe notitie',
                onPressed: () => editNote(context,
                    tag: _filter.startsWith('#') ? _filter.substring(1) : null),
                child: const Icon(Icons.add),
              ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Zoeken',
                  isDense: true),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final w in [
                  _chip('Alle', 'all'),
                  _chip('Los', 'loose', icon: Icons.notes),
                  _chip('Klussen', 'jobs', icon: Icons.event_note),
                  _chip('Afgelopen klussen', 'past',
                      icon: Icons.inventory_2_outlined),
                  for (final t in tags) _chip('#$t', '#$t'),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Tag'),
                    onPressed: () async {
                      await pickTags(context);
                      setState(() {});
                    },
                  ),
                ])
                  Padding(padding: const EdgeInsets.only(right: 6), child: w),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? ListView(children: const [
                    EmptyHint(
                        icon: Icons.sticky_note_2_outlined,
                        title: 'Geen notities',
                        body:
                            'Maak een notitie met de +. Houd een notitie vast om te selecteren '
                            'of hem op een tag te slepen; met ≡ verander je de volgorde.'),
                  ])
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: shown.length,
                    onReorder: (o, n) => _reorder(List.of(shown), o, n),
                    itemBuilder: (context, i) {
                      final n = shown[i];
                      return _NoteTile(
                        key: ValueKey(n.id),
                        note: n,
                        index: i,
                        selected: _selected.contains(n.id),
                        selecting: _selecting,
                        dragCount: _selected.isEmpty
                            ? 1
                            : {..._selected, n.id}.length,
                        onTap: () {
                          if (_selecting) {
                            setState(() => _selected.contains(n.id)
                                ? _selected.remove(n.id)
                                : _selected.add(n.id));
                          } else {
                            editNote(context, note: n);
                          }
                        },
                        onDragStart: () => setState(() => _selected.add(n.id)),
                      );
                    },
                  ),
          ),
        ]),
      );
    });
  }
}

class _NoteTile extends StatelessWidget {
  final Note note;
  final int index;
  final bool selected;
  final bool selecting;
  final int dragCount;
  final VoidCallback onTap;
  final VoidCallback onDragStart;

  const _NoteTile({
    super.key,
    required this.note,
    required this.index,
    required this.selected,
    required this.selecting,
    required this.dragCount,
    required this.onTap,
    required this.onDragStart,
  });

  @override
  Widget build(BuildContext context) {
    final n = note;
    final primary = Theme.of(context).colorScheme.primary;
    final job = store.job(n.jobKey);
    final body = n.title.trim().isEmpty
        ? n.text.split('\n').skip(1).join('\n')
        : n.text;
    final card = Card(
      color: selected ? primary.withValues(alpha: 0.16) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected ? BorderSide(color: primary) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? primary : muted),
              ),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (n.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.push_pin, size: 14, color: primary),
                        ),
                      if (n.lockscreen)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child:
                              Icon(Icons.lock_outline, size: 14, color: muted),
                        ),
                      Expanded(
                        child: Text(n.heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                    ]),
                    if (body.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(body.trim(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFB8B6AF))),
                      ),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 2, children: [
                      Text('${dateShort(n.updated)} ${hm(n.updated)}',
                          style: const TextStyle(color: muted, fontSize: 12)),
                      if (job != null)
                        GestureDetector(
                          onTap: () => openJob(context, job.key),
                          child: Text('${store.clientName(job)} · ${job.title}',
                              style: TextStyle(color: primary, fontSize: 12)),
                        ),
                      for (final t in n.tags)
                        Text('#$t',
                            style:
                                const TextStyle(color: muted, fontSize: 12)),
                    ]),
                  ]),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle, color: muted),
              ),
            ),
          ]),
        ),
      ),
    );

    // Lang indrukken: selecteren en slepen naar een tag.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LongPressDraggable<String>(
        data: n.id,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: onDragStart,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2B2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primary),
            ),
            child: Text(
                dragCount > 1
                    ? '$dragCount notities · sleep naar een tag'
                    : '${n.heading} · sleep naar een tag',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: card),
        child: card,
      ),
    );
  }
}
