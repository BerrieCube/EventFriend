import 'dart:convert';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../device.dart';
import '../format.dart';
import '../note_text.dart';
import '../store.dart';
import 'common.dart';
import 'job_detail.dart';

const _cardColor = Color(0xFF1B1C1F);
const _line = Color(0xFF2E2F33);

Color spaceColor(String s) => Color(store.spaceColor(s));

/// Privé is ontgrendeld tot de app naar de achtergrond gaat.
bool privateUnlocked = false;

/// Vraagt de pincode voor Privé (als die is ingesteld). true = toegang.
Future<bool> unlockPrivate(BuildContext context) async {
  final pin = store.privatePin;
  if (pin == null || privateUnlocked) return true;
  final ctrl = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      void check() {
        if (ctrl.text == pin) {
          Navigator.pop(c, true);
        } else {
          setS(() => err = 'Onjuiste pincode');
          ctrl.clear();
        }
      }

      return AlertDialog(
        title: Text('${store.spaceName('private')} openen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Pincode', errorText: err),
          onSubmitted: (_) => check(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuleren')),
          FilledButton(onPressed: check, child: const Text('Openen')),
        ],
      );
    }),
  );
  if (ok == true) privateUnlocked = true;
  return ok == true;
}

/// Notitie maken of wijzigen. Met [job] wordt hij aan die klus gekoppeld.
/// Op een groot scherm opent de editor als venster, anders schermvullend.
Future<void> editNote(BuildContext context,
    {Note? note,
    Job? job,
    String? tag,
    String space = 'work',
    bool checklist = false,
    bool photo = false}) {
  final editor = _NoteEditor(
      note: note,
      job: job,
      tag: tag,
      space: space,
      checklist: checklist,
      photo: photo);
  if (MediaQuery.sizeOf(context).width >= 800) {
    return showDialog(
      context: context,
      builder: (c) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
          child: editor,
        ),
      ),
    );
  }
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => editor));
}

// ============================================================ Editor

class _NoteEditor extends StatefulWidget {
  final Note? note;
  final Job? job;
  final String? tag;
  final String space;
  final bool checklist;
  final bool photo;
  const _NoteEditor(
      {this.note,
      this.job,
      this.tag,
      this.space = 'work',
      this.checklist = false,
      this.photo = false});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final String _id = widget.note?.id ?? newId();
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final QuillController _quill;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late String? _jobKey = widget.note?.jobKey ?? widget.job?.key;
  late String _space = widget.note?.space ?? widget.space;
  late bool _lock = widget.note?.lockscreen ?? false;
  late bool _widget = widget.note?.widget ?? false;
  late bool _pinned = widget.note?.pinned ?? false;
  late bool _archived = widget.note?.archived ?? false;
  late final List<String> _tags = [
    ...?widget.note?.tags,
    if (widget.note == null && widget.tag != null) widget.tag!,
  ];
  bool _format = false;
  bool _saved = false;
  // Afgevinkte checklist-items staan los van de editor, ingeklapt onderaan.
  final _checked = <NoteLine>[];
  bool _showChecked = false;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    final delta = n?.content ?? (n == null ? null : plainToDelta(n.text));
    Document doc;
    try {
      doc = delta != null
          ? Document.fromJson(_splitChecked(jsonDecode(delta) as List))
          : widget.checklist
              ? Document.fromJson([
                  {
                    'insert': '\n',
                    'attributes': {'list': 'unchecked'}
                  }
                ])
              : Document();
    } catch (_) {
      doc = Document()..insert(0, n?.text ?? '');
    }
    _quill = QuillController(
        document: doc, selection: const TextSelection.collapsed(offset: 0));
    _quill.addListener(_onChange);
    if (widget.photo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addImage());
    } else if (widget.note == null) {
      // Nieuwe notitie: meteen in de tekst beginnen.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  void dispose() {
    _quill.removeListener(_onChange);
    _quill.dispose();
    _focus.dispose();
    _scroll.dispose();
    _title.dispose();
    super.dispose();
  }

  /// Haalt afgevinkte regels uit [ops] (naar [_checked]) en geeft de rest.
  List<Map<String, dynamic>> _splitChecked(List ops) {
    final lines = splitLines(ops);
    _checked.addAll(lines.where((l) => l.isChecked));
    final rest = lines.where((l) => !l.isChecked).toList();
    return joinLines(rest.isEmpty ? [NoteLine([], null)] : rest);
  }

  List<Map<String, dynamic>> get _docOps =>
      List<Map<String, dynamic>>.from(_quill.document.toDelta().toJson());

  void _setDoc(List<Map<String, dynamic>> ops) {
    _moving = true;
    final sel = _quill.selection.baseOffset;
    _quill.document = Document.fromJson(ops);
    final len = _quill.document.length;
    _quill.updateSelection(
        TextSelection.collapsed(offset: min(max0(sel), len - 1)),
        ChangeSource.local);
    _moving = false;
  }

  static int max0(int v) => v < 0 ? 0 : v;

  /// Net afgevinkt in de editor: naar het blok "afgevinkte items".
  void _onChange() {
    if (_moving) return;
    final hasChecked = _docOps.any((o) =>
        o['attributes'] is Map && (o['attributes'] as Map)['list'] == 'checked');
    if (!hasChecked) return;
    Future.microtask(() {
      if (!mounted) return;
      final before = _checked.length;
      final ops = _splitChecked(_docOps);
      if (_checked.length == before) return;
      _setDoc(ops);
      setState(() {});
    });
  }

  /// Afgevinkt item terugzetten: na het laatste open checklist-item.
  void _uncheck(int i) {
    final l = _checked.removeAt(i)..setChecked(false);
    final lines = splitLines(_docOps);
    var at = lines.lastIndexWhere((x) => x.isCheckItem) + 1;
    if (at == 0) {
      at = lines.isNotEmpty && lines.last.plain.trim().isEmpty
          ? lines.length - 1
          : lines.length;
    }
    lines.insert(at, l);
    _setDoc(joinLines(lines));
    setState(() {});
  }

  void _deleteChecked() {
    final removed = List.of(_checked);
    setState(_checked.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      persist: false,
      content: Text('${removed.length} afgevinkte item(s) verwijderd'),
      action: SnackBarAction(
          label: 'Ongedaan',
          onPressed: () {
            if (mounted) setState(() => _checked.addAll(removed));
          }),
    ));
  }

  String get _content =>
      jsonEncode(joinLines([...splitLines(_docOps), ..._checked]));

  /// Opslaan en sluiten. Lege notities zonder foto's worden niet bewaard.
  Future<void> _save({SnackBar? after}) async {
    if (_saved) return;
    _saved = true;
    final messenger = ScaffoldMessenger.of(context);
    final content = _content;
    final plain = deltaToPlain(content);
    final title = _title.text.trim();
    final images = store.noteImages(_id);
    if (plain.trim().isEmpty && title.isEmpty && images.isEmpty) {
      if (widget.note != null) {
        await store.trashNote(widget.note!);
        messenger.showSnackBar(
            const SnackBar(content: Text('Lege notitie naar de prullenbak')));
      }
      if (mounted) Navigator.pop(context);
      return;
    }
    final now = DateTime.now();
    final n = widget.note ?? Note(id: _id, text: '', created: now, updated: now);
    if (widget.note == null) n.order = store.topOrder;
    final changed = widget.note == null ||
        n.title != title ||
        n.content != content ||
        n.tags.join(',') != _tags.join(',') ||
        n.jobKey != _jobKey;
    n.title = title;
    n.content = content;
    n.text = plain;
    n.jobKey = _jobKey;
    n.jobTitle = store.job(_jobKey)?.title;
    n.space = _jobKey != null ? 'work' : _space;
    n.lockscreen = _lock;
    n.pinned = _pinned && !_archived;
    n.archived = _archived;
    n.tags = List.of(_tags);
    if (_widget && !n.widget) {
      for (final o in store.notes.where((o) => o.widget && o.id != n.id)) {
        o.widget = false;
        await store.saveNote(o, touch: false);
      }
    }
    n.widget = _widget;
    await store.saveNote(n, touch: changed);
    if (after != null) messenger.showSnackBar(after);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Foto maken'),
              onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Afbeelding kiezen'),
              onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final x = await ImagePicker()
          .pickImage(source: source, maxWidth: 1800, imageQuality: 80);
      if (x == null) return;
      await store.addPhoto('note:$_id', await x.readAsBytes());
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Afbeelding toevoegen mislukt: $e')));
      }
    }
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.label_outline),
                title: const Text('Labels'),
                subtitle: _tags.isEmpty ? null : Text(_tags.join(', ')),
                onTap: () async {
                  Navigator.pop(c);
                  await _editTags();
                },
              ),
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
                onChanged: (v) => both(() {
                  _jobKey = v;
                  if (v != null) _space = 'work';
                }),
              ),
              const SizedBox(height: 8),
              if (_jobKey == null)
                Row(children: [
                  const Text('Omgeving'),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: [
                      for (final s in Store.spaces)
                        ButtonSegment(value: s, label: Text(store.spaceName(s))),
                    ],
                    selected: {_space},
                    onSelectionChanged: (v) => both(() => _space = v.first),
                  ),
                ])
              else
                Text('Klusnotities staan altijd in ${store.spaceName('work')}.',
                    style: const TextStyle(color: muted, fontSize: 12)),
              if (device.supported)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Op widget'),
                  subtitle:
                      const Text('Toont deze notitie in de notitie-widget'),
                  value: _widget,
                  onChanged: (v) => both(() => _widget = v),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.share_outlined),
                title: const Text('Delen'),
                onTap: () {
                  Navigator.pop(c);
                  final t = _title.text.trim();
                  final body = deltaToPlain(_content);
                  SharePlus.instance.share(ShareParams(
                      text: t.isEmpty ? body : '$t\n\n$body',
                      subject: t.isEmpty ? null : t));
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Kopie maken'),
                onTap: () async {
                  Navigator.pop(c);
                  final now = DateTime.now();
                  final content = _content;
                  await store.saveNote(Note(
                    id: newId(),
                    title: _title.text.trim(),
                    text: deltaToPlain(content),
                    content: content,
                    jobKey: _jobKey,
                    jobTitle: store.job(_jobKey)?.title,
                    created: now,
                    updated: now,
                    tags: List.of(_tags),
                    space: _space,
                    order: store.topOrder,
                  ));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kopie gemaakt')));
                  }
                },
              ),
              if (widget.note != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Verwijderen'),
                  subtitle: const Text('Naar de prullenbak (7 dagen herstelbaar)'),
                  onTap: () async {
                    Navigator.pop(c);
                    _saved = true;
                    final messenger = ScaffoldMessenger.of(context);
                    final n = widget.note!;
                    await store.trashNote(n);
                    messenger.showSnackBar(SnackBar(
        persist: false,
                      content: const Text('Notitie naar de prullenbak'),
                      action: SnackBarAction(
                          label: 'Ongedaan',
                          onPressed: () => store.restoreNote(n)),
                    ));
                    if (mounted) Navigator.pop(context);
                  },
                ),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _editTags() async {
    final r = await pickTags(context,
        selected: _tags.toSet(), space: _jobKey != null ? 'work' : _space);
    if (r != null) {
      setState(() => _tags
        ..clear()
        ..addAll(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = store.job(_jobKey);
    final images = store.noteImages(_id);
    final updated = widget.note?.updated;
    final primary = Theme.of(context).colorScheme.primary;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Scaffold(
        backgroundColor: _cardColor,
        appBar: AppBar(
          backgroundColor: _cardColor,
          leading: IconButton(
              tooltip: 'Opslaan en sluiten',
              icon: const Icon(Icons.arrow_back),
              onPressed: _save),
          actions: [
            IconButton(
              tooltip: _pinned ? 'Losmaken' : 'Vastzetten',
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () => setState(() {
                _pinned = !_pinned;
                if (_pinned) _archived = false;
              }),
            ),
            if (device.supported)
              IconButton(
                tooltip: _lock
                    ? 'Van vergrendelscherm halen'
                    : 'Op vergrendelscherm zetten',
                icon: Icon(_lock ? Icons.lock : Icons.lock_outline,
                    color: _lock ? primary : null),
                onPressed: () async {
                  if (!_lock && !await device.requestPermission()) return;
                  setState(() => _lock = !_lock);
                },
              ),
            IconButton(
              tooltip: _archived ? 'Uit archief halen' : 'Archiveren',
              icon: Icon(_archived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined),
              onPressed: () {
                final was = _archived;
                setState(() {
                  _archived = !_archived;
                  if (_archived) _pinned = false;
                });
                _save(
                    after: SnackBar(
                        content: Text(was
                            ? 'Notitie uit archief gehaald'
                            : 'Notitie gearchiveerd')));
              },
            ),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (images.isNotEmpty) ...[
                  _ImageStrip(images: images, onChanged: () => setState(() {})),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: 'Titel',
                    filled: false,
                    border: InputBorder.none,
                  ),
                ),
                QuillEditor(
                  controller: _quill,
                  focusNode: _focus,
                  scrollController: ScrollController(),
                  config: QuillEditorConfig(
                    placeholder: 'Notitie',
                    autoFocus: widget.note == null && !widget.photo,
                    scrollable: false,
                    expands: false,
                    padding: EdgeInsets.zero,
                    minHeight: 160,
                  ),
                ),
                if (_checked.isNotEmpty) ...[
                  const Divider(color: _line, height: 20),
                  InkWell(
                    onTap: () => setState(() => _showChecked = !_showChecked),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Icon(_showChecked
                            ? Icons.expand_less
                            : Icons.expand_more),
                        const SizedBox(width: 6),
                        Text(
                            _checked.length == 1
                                ? '1 afgevinkt item'
                                : '${_checked.length} afgevinkte items',
                            style: const TextStyle(color: muted)),
                      ]),
                    ),
                  ),
                  if (_showChecked) ...[
                    for (var i = 0; i < _checked.length; i++)
                      Row(children: [
                        Checkbox(
                          value: true,
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) => _uncheck(i),
                        ),
                        Expanded(
                          child: Text(_checked[i].plain,
                              style: const TextStyle(
                                  color: muted,
                                  decoration: TextDecoration.lineThrough)),
                        ),
                      ]),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _deleteChecked,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Afgevinkte items verwijderen'),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (job != null)
                    ActionChip(
                      avatar: Icon(Icons.event_note, size: 16, color: primary),
                      label: Text('${store.clientName(job)} · ${job.title}'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => openJob(context, job.key),
                    ),
                  if (job == null && store.notesSpace == 'all')
                    Chip(
                      label: Text(store.spaceName(_space)),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: spaceColor(_space)),
                    ),
                  for (final t in _tags)
                    InputChip(
                      label: Text(t),
                      visualDensity: VisualDensity.compact,
                      onPressed: _editTags,
                      onDeleted: () => setState(() => _tags.remove(t)),
                    ),
                ]),
              ],
            ),
          ),
          if (_format)
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
                showUndo: false,
                showRedo: false,
              ),
            ),
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _line))),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [
                IconButton(
                    tooltip: 'Afbeelding toevoegen',
                    icon: const Icon(Icons.add_box_outlined),
                    onPressed: _addImage),
                IconButton(
                    tooltip: 'Opmaak',
                    isSelected: _format,
                    icon: const Icon(Icons.text_format),
                    onPressed: () => setState(() => _format = !_format)),
                IconButton(
                    tooltip: 'Checklist',
                    icon: const Icon(Icons.check_box_outlined),
                    onPressed: () {
                      final isList = _quill
                              .getSelectionStyle()
                              .attributes['list']
                              ?.value !=
                          null;
                      _quill.formatSelection(isList
                          ? Attribute.clone(Attribute.unchecked, null)
                          : Attribute.unchecked);
                    }),
                Expanded(
                  child: Text(
                    updated == null
                        ? ''
                        : sameDay(updated, DateTime.now())
                            ? 'Bewerkt ${hm(updated)}'
                            : 'Bewerkt ${dateShort(updated)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
                IconButton(
                    tooltip: 'Meer',
                    icon: const Icon(Icons.more_vert),
                    onPressed: _more),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Afbeeldingen bovenaan een notitie.
class _ImageStrip extends StatelessWidget {
  final List<Photo> images;
  final VoidCallback onChanged;
  const _ImageStrip({required this.images, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget img(Photo p, {double? h}) => GestureDetector(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _NoteImageView(photo: p)));
            onChanged();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(p.bytes,
                height: h, width: double.infinity, fit: BoxFit.cover),
          ),
        );
    if (images.length == 1) return img(images.first, h: 220);
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => SizedBox(width: 160, child: img(images[i])),
      ),
    );
  }
}

class _NoteImageView extends StatelessWidget {
  final Photo photo;
  const _NoteImageView({required this.photo});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, actions: [
          IconButton(
            tooltip: 'Afbeelding verwijderen',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(context, 'Afbeelding verwijderen?',
                  'De afbeelding wordt uit de notitie verwijderd.')) {
                await store.deletePhoto(photo.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ]),
        body: InteractiveViewer(
            maxScale: 8, child: Center(child: Image.memory(photo.bytes))),
      );
}

// ============================================================ Labels kiezen

/// Laat labels kiezen en nieuwe aanmaken. Geeft null bij annuleren.
Future<Set<String>?> pickTags(BuildContext context,
    {Set<String> selected = const {}, String space = 'work'}) {
  final sel = {...selected};
  final ctrl = TextEditingController();
  return showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      final tags = {...store.tagsIn(space), ...sel}.toList()..sort();
      void add() {
        final t = ctrl.text.trim().replaceAll('#', '');
        if (t.isEmpty) return;
        store.addTag(t, space: space == 'all' ? 'work' : space);
        setS(() {
          sel.add(t);
          ctrl.clear();
        });
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 16 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Labels',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                    hintText: 'Nieuw label, bijv. LED of Barco', isDense: true),
                onSubmitted: (_) => add(),
              ),
            ),
            IconButton(onPressed: add, icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in tags)
              FilterChip(
                label: Text(t),
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

/// Labels hernoemen, verwijderen en toevoegen.
Future<void> editLabels(BuildContext context, String space) async {
  final ctrl = TextEditingController();
  final target = space == 'all' ? 'work' : space;
  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      final tags = store.tagsIn(space);
      return AlertDialog(
        title: const Text('Labels bewerken'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                      hintText: 'Nieuw label', isDense: true),
                  onSubmitted: (v) async {
                    if (v.trim().isEmpty) return;
                    await store.addTag(v.trim(), space: target);
                    ctrl.clear();
                    setS(() {});
                  },
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () async {
                    if (ctrl.text.trim().isEmpty) return;
                    await store.addTag(ctrl.text.trim(), space: target);
                    ctrl.clear();
                    setS(() {});
                  }),
            ]),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final t in tags)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.label_outline),
                    title: Text(t),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Hernoemen',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () async {
                          final r = TextEditingController(text: t);
                          final name = await showDialog<String>(
                            context: c,
                            builder: (d) => AlertDialog(
                              title: const Text('Label hernoemen'),
                              content: TextField(controller: r, autofocus: true),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(d),
                                    child: const Text('Annuleren')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(d, r.text.trim()),
                                    child: const Text('Opslaan')),
                              ],
                            ),
                          );
                          if (name != null && name.isNotEmpty && name != t) {
                            await store.renameTag(t, name, space: space);
                            setS(() {});
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Verwijderen',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          if (await confirm(c, 'Label "$t" verwijderen?',
                              'Het label wordt van alle notities gehaald. De notities zelf blijven bestaan.')) {
                            await store.removeTag(t, space: space);
                            setS(() {});
                          }
                        },
                      ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('Klaar')),
        ],
      );
    }),
  );
}

// ============================================================ Overzicht

/// Weergaven: 'notes', 'jobs', 'past', 'loose', '#label', 'archive', 'trash'.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();
  late final AppLifecycleListener _life;
  String _q = '';
  String _view = 'notes';
  late String _space = store.notesSpace;
  final _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;
  bool get _needsPin =>
      _space != 'work' && store.privatePin != null && !privateUnlocked;

  @override
  void initState() {
    super.initState();
    // Privé weer op slot zodra de app naar de achtergrond gaat.
    _life = AppLifecycleListener(onHide: () {
      if (store.privatePin != null) {
        privateUnlocked = false;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _life.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _setSpace(String s) async {
    if (s != 'work' && !await unlockPrivate(context)) return;
    await store.setNotesSpace(s);
    setState(() {
      _space = s;
      _selected.clear();
      if (_view.startsWith('#')) _view = 'notes';
    });
  }

  /// Omgeving voor nieuwe notities.
  String get _newSpace => _space == 'all' ? 'work' : _space;

  bool _inSpace(Note n) => _space == 'all' || n.space == _space;

  bool _matches(Note n) {
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      // Zoeken gaat door alles in de omgeving, ook het archief.
      return _inSpace(n) &&
          (n.title.toLowerCase().contains(q) ||
              n.text.toLowerCase().contains(q) ||
              (n.jobTitle ?? '').toLowerCase().contains(q) ||
              n.tags.any((t) => t.toLowerCase().contains(q)));
    }
    if (!_inSpace(n)) return false;
    final now = DateTime.now();
    final j = store.job(n.jobKey);
    return switch (_view) {
      'archive' => n.archived,
      'notes' => !n.archived,
      'loose' => !n.archived && n.jobKey == null,
      'jobs' => !n.archived && j != null && !j.end.isBefore(now),
      'past' => !n.archived && j != null && j.end.isBefore(now),
      _ => !n.archived && n.tags.contains(_view.substring(1)),
    };
  }

  List<Note> get _shown => _view == 'trash'
      ? store.trashedNotes.where(_inSpace).toList()
      : store.notes.where(_matches).toList();

  String get _title => switch (_view) {
        'notes' => 'Notities',
        'jobs' => 'Bij klussen',
        'past' => 'Afgelopen klussen',
        'loose' => 'Losse notities',
        'archive' => 'Archief',
        'trash' => 'Prullenbak',
        _ => _view.substring(1),
      };

  List<Note> get _selectedNotes => [
        ...store.notes,
        ...store.trashedNotes
      ].where((n) => _selected.contains(n.id)).toList();

  void _toggle(Note n) => setState(() =>
      _selected.contains(n.id) ? _selected.remove(n.id) : _selected.add(n.id));

  Future<void> _pinSelected() async {
    final notes = _selectedNotes;
    final pin = notes.any((n) => !n.pinned);
    for (final n in notes) {
      n.pinned = pin;
      if (pin) n.archived = false;
      await store.saveNote(n, touch: false);
    }
    setState(_selected.clear);
  }

  Future<void> _archiveSelected(bool archive) async {
    final notes = _selectedNotes;
    for (final n in notes) {
      n.archived = archive;
      if (archive) n.pinned = false;
      await store.saveNote(n, touch: false);
    }
    setState(_selected.clear);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        persist: false,
        content: Text(archive
            ? '${notes.length} notitie(s) gearchiveerd'
            : '${notes.length} notitie(s) uit archief gehaald'),
        action: SnackBarAction(
            label: 'Ongedaan',
            onPressed: () async {
              for (final n in notes) {
                n.archived = !archive;
                await store.saveNote(n, touch: false);
              }
            }),
      ));
    }
  }

  Future<void> _trashSelected() async {
    final notes = _selectedNotes;
    for (final n in notes) {
      await store.trashNote(n);
    }
    setState(_selected.clear);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        persist: false,
        content: Text('${notes.length} notitie(s) naar de prullenbak'),
        action: SnackBarAction(
            label: 'Ongedaan',
            onPressed: () async {
              for (final n in notes) {
                await store.restoreNote(n);
              }
            }),
      ));
    }
  }

  Future<void> _restoreSelected() async {
    for (final n in _selectedNotes) {
      await store.restoreNote(n);
    }
    setState(_selected.clear);
  }

  Future<void> _purgeSelected() async {
    final ids = _selected.toList();
    if (!await confirm(context, '${ids.length} notitie(s) definitief verwijderen?',
        'Dit kan niet ongedaan worden gemaakt.')) {
      return;
    }
    for (final id in ids) {
      await store.purgeNote(id);
    }
    setState(_selected.clear);
  }

  Future<void> _tagSelected() async {
    final notes = _selectedNotes;
    final common = notes.isEmpty
        ? <String>{}
        : notes.map((n) => n.tags.toSet()).reduce((a, b) => a.intersection(b));
    final r = await pickTags(context, selected: common, space: _space);
    if (r == null) return;
    final removed = common.difference(r);
    for (final n in notes) {
      n.tags = {...n.tags.where((t) => !removed.contains(t)), ...r}.toList();
      await store.saveNote(n, touch: false);
    }
    setState(_selected.clear);
  }

  /// Gesleepte notitie(s) op een label in het zijmenu losgelaten.
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
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ids.length} notitie(s) gelabeld met $tag')));
    }
  }

  /// Gesleepte notitie vóór [target] zetten.
  Future<void> _moveBefore(String id, Note target, List<Note> shown) async {
    if (id == target.id) return;
    final moved = store.note(id);
    if (moved == null) return;
    final list = shown.where((n) => n.id != id).toList();
    final i = list.indexWhere((n) => n.id == target.id);
    if (i < 0) return;
    final before = i > 0 ? list[i - 1] : null;
    moved.order = before == null
        ? target.order - 1
        : (before.order + target.order) / 2;
    moved.pinned = target.pinned;
    await store.saveNote(moved, touch: false);
    setState(_selected.clear);
  }

  void _openNote(Note n) {
    if (_selecting) {
      _toggle(n);
      return;
    }
    if (n.trashed != null) {
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(n.heading,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.restore_from_trash_outlined),
              title: const Text('Herstellen'),
              onTap: () {
                Navigator.pop(c);
                store.restoreNote(n);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Definitief verwijderen'),
              onTap: () async {
                Navigator.pop(c);
                if (await confirm(context, 'Definitief verwijderen?',
                    'Dit kan niet ongedaan worden gemaakt.')) {
                  await store.purgeNote(n.id);
                }
              },
            ),
          ]),
        ),
      );
      return;
    }
    editNote(context, note: n);
  }

  void _new({bool checklist = false, bool photo = false}) => editNote(context,
      tag: _view.startsWith('#') ? _view.substring(1) : null,
      space: _newSpace,
      checklist: checklist,
      photo: photo);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return StoreBuilder(builder: (context) {
      final menu = _Menu(
        space: _space,
        view: _view,
        wide: wide,
        onSpace: (s) {
          if (!wide) Navigator.pop(context);
          _setSpace(s);
        },
        onView: (v) {
          if (!wide) Navigator.pop(context);
          setState(() {
            _view = v;
            _selected.clear();
            _q = '';
            _search.clear();
          });
        },
        onDropTag: _dropOnTag,
      );
      final canCreate =
          !_needsPin && _view != 'trash' && _view != 'archive' && !_selecting;
      return Scaffold(
        key: _scaffold,
        drawer: wide ? null : Drawer(backgroundColor: _cardColor, child: menu),
        bottomNavigationBar: !wide && canCreate
            ? _CreateBar(onTap: _new, bottom: true)
            : null,
        body: SafeArea(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (wide) SizedBox(width: 260, child: menu),
            Expanded(child: _content(wide, canCreate)),
          ]),
        ),
      );
    });
  }

  Widget _content(bool wide, bool canCreate) {
    if (_needsPin) {
      return Column(children: [
        _topBar(wide),
        Expanded(
          child: EmptyHint(
            icon: Icons.lock_outline,
            title: '${store.spaceName('private')} is vergrendeld',
            body: 'Voer je pincode in om deze notities te zien.',
            action: FilledButton.icon(
              onPressed: () async {
                if (await unlockPrivate(context)) setState(() {});
              },
              icon: const Icon(Icons.lock_open),
              label: const Text('Ontgrendelen'),
            ),
          ),
        ),
      ]);
    }
    final shown = _shown;
    final searching = _q.trim().isNotEmpty;
    final sections = <(String?, List<Note>)>[];
    if (!searching && _view != 'trash' && _view != 'archive') {
      final pinned = shown.where((n) => n.pinned).toList();
      final other = shown.where((n) => !n.pinned).toList();
      if (pinned.isNotEmpty) {
        sections.add(('Vastgezet', pinned));
        if (other.isNotEmpty) sections.add(('Overige', other));
      } else {
        sections.add((null, other));
      }
    } else {
      sections.add((null, shown));
    }

    return LayoutBuilder(builder: (context, box) {
      final grid = store.notesGrid;
      final cols = grid ? (box.maxWidth / 250).floor().clamp(2, 5) : 1;
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _topBar(wide),
          if (wide && canCreate)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _CreateBar(onTap: _new),
                ),
              ),
            ),
          if (_view == 'trash')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(children: [
                const Expanded(
                  child: Text(
                      'Notities in de prullenbak worden na 7 dagen definitief verwijderd.',
                      style: TextStyle(color: muted)),
                ),
                if (shown.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      if (await confirm(context, 'Prullenbak leegmaken?',
                          '${shown.length} notitie(s) worden definitief verwijderd.')) {
                        for (final n in shown) {
                          await store.purgeNote(n.id);
                        }
                      }
                    },
                    child: const Text('Prullenbak leegmaken'),
                  ),
              ]),
            ),
          if (shown.isEmpty)
            EmptyHint(
              icon: switch (_view) {
                'archive' => Icons.archive_outlined,
                'trash' => Icons.delete_outline,
                _ => Icons.lightbulb_outline,
              },
              title: searching
                  ? 'Niets gevonden'
                  : switch (_view) {
                      'archive' => 'Geen gearchiveerde notities',
                      'trash' => 'De prullenbak is leeg',
                      _ => 'Hier komen je notities',
                    },
              body: searching
                  ? 'Probeer een ander woord.'
                  : _view == 'trash' || _view == 'archive'
                      ? ''
                      : 'Maak een notitie met "Notitie maken". Houd een notitie vast '
                          'om te selecteren of te verslepen.',
            ),
          for (final sec in sections) ...[
            if (sec.$1 != null && sec.$2.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 6),
                child: Text(sec.$1!.toUpperCase(),
                    style: const TextStyle(
                        color: muted, fontSize: 11, letterSpacing: 0.8)),
              ),
            if (sec.$2.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _Masonry(
                  columns: cols,
                  width: box.maxWidth - 20,
                  notes: sec.$2,
                  builder: (n, w) => _draggable(n, w, shown),
                ),
              ),
          ],
        ],
      );
    });
  }

  Widget _topBar(bool wide) {
    if (_selecting) {
      final inTrash = _view == 'trash';
      final allArchived = _selectedNotes.every((n) => n.archived);
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(children: [
          IconButton(
              tooltip: 'Klaar',
              icon: const Icon(Icons.close),
              onPressed: () => setState(_selected.clear)),
          Expanded(
              child: Text('${_selected.length}',
                  style: const TextStyle(fontSize: 18))),
          if (inTrash) ...[
            IconButton(
                tooltip: 'Herstellen',
                icon: const Icon(Icons.restore_from_trash_outlined),
                onPressed: _restoreSelected),
            IconButton(
                tooltip: 'Definitief verwijderen',
                icon: const Icon(Icons.delete_forever_outlined),
                onPressed: _purgeSelected),
          ] else ...[
            IconButton(
                tooltip: 'Vastzetten / losmaken',
                icon: const Icon(Icons.push_pin_outlined),
                onPressed: _pinSelected),
            IconButton(
                tooltip: 'Labels',
                icon: const Icon(Icons.label_outline),
                onPressed: _tagSelected),
            IconButton(
                tooltip: allArchived ? 'Uit archief halen' : 'Archiveren',
                icon: Icon(allArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined),
                onPressed: () => _archiveSelected(!allArchived)),
            IconButton(
                tooltip: 'Verwijderen',
                icon: const Icon(Icons.delete_outline),
                onPressed: _trashSelected),
          ],
        ]),
      );
    }
    final accent = _space == 'all'
        ? Theme.of(context).colorScheme.primary
        : spaceColor(_space);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(children: [
          if (!wide)
            IconButton(
                tooltip: 'Menu',
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffold.currentState?.openDrawer())
          else
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.search, color: muted)),
          Expanded(
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: _view == 'notes'
                    ? 'Zoeken in ${_space == 'all' ? 'alle notities' : store.spaceName(_space)}'
                    : '$_title · zoeken',
                filled: false,
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          if (_q.isNotEmpty)
            IconButton(
                tooltip: 'Wissen',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                      _q = '';
                      _search.clear();
                    })),
          IconButton(
            tooltip: store.notesGrid ? 'Lijstweergave' : 'Rasterweergave',
            icon: Icon(store.notesGrid
                ? Icons.view_agenda_outlined
                : Icons.grid_view_outlined),
            onPressed: () => store.setNotesGrid(!store.notesGrid),
          ),
          // Omgeving in één oogopslag; tikken = wisselen.
          Tooltip(
            message: 'Omgeving wisselen',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _setSpace(switch (_space) {
                'work' => 'private',
                'private' => 'all',
                _ => 'work',
              }),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: accent.withValues(alpha: 0.25),
                child: Text(
                  _space == 'all'
                      ? '∗'
                      : store.spaceName(_space).characters.first.toUpperCase(),
                  style: TextStyle(
                      color: accent, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ),
          const SettingsAction(),
        ]),
      ),
    );
  }

  Widget _draggable(Note n, double width, List<Note> shown) {
    final card = NoteCard(
      note: n,
      selected: _selected.contains(n.id),
      showSpace: _space == 'all',
      onTap: () => _openNote(n),
    );
    if (n.trashed != null) {
      return GestureDetector(onLongPress: () => _toggle(n), child: card);
    }
    // Lang indrukken = selecteren; meteen slepen = verplaatsen of op label leggen.
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != n.id,
      onAcceptWithDetails: (d) => _moveBefore(d.data, n, shown),
      builder: (context, cand, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.only(top: cand.isEmpty ? 0 : 24),
        child: LongPressDraggable<String>(
          data: n.id,
          onDragStarted: () {
            HapticFeedback.selectionClick();
            setState(() => _selected.add(n.id));
          },
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: width,
              child: Opacity(opacity: 0.9, child: card),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: card),
          child: card,
        ),
      ),
    );
  }
}

/// "Notitie maken…" met snelknoppen voor checklist en afbeelding.
class _CreateBar extends StatelessWidget {
  final void Function({bool checklist, bool photo}) onTap;
  final bool bottom;
  const _CreateBar({required this.onTap, this.bottom = false});

  @override
  Widget build(BuildContext context) {
    final bar = Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(bottom ? 0 : 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(bottom ? 0 : 12),
        onTap: () => onTap(),
        child: Container(
          height: 52,
          padding: const EdgeInsets.only(left: 16),
          decoration: bottom
              ? const BoxDecoration(border: Border(top: BorderSide(color: _line)))
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _line)),
          child: Row(children: [
            const Expanded(
                child: Text('Notitie maken…',
                    style: TextStyle(color: muted, fontSize: 15))),
            IconButton(
                tooltip: 'Nieuwe checklist',
                icon: const Icon(Icons.check_box_outlined),
                onPressed: () => onTap(checklist: true)),
            IconButton(
                tooltip: 'Nieuwe notitie met afbeelding',
                icon: const Icon(Icons.image_outlined),
                onPressed: () => onTap(photo: true)),
            const SizedBox(width: 4),
          ]),
        ),
      ),
    );
    return bottom ? SafeArea(top: false, child: bar) : bar;
  }
}

/// Zijmenu: omgeving, weergaven, labels, archief en prullenbak.
class _Menu extends StatelessWidget {
  final String space;
  final String view;
  final bool wide;
  final ValueChanged<String> onSpace;
  final ValueChanged<String> onView;
  final Future<void> Function(String id, String tag) onDropTag;
  const _Menu(
      {required this.space,
      required this.view,
      required this.wide,
      required this.onSpace,
      required this.onView,
      required this.onDropTag});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final accent = space == 'all' ? primary : spaceColor(space);
    final tags = store.tagsIn(space);

    Widget item(IconData icon, String label, String v) {
      final sel = view == v;
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Material(
          color: sel ? accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(24)),
          child: InkWell(
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(24)),
            onTap: () => onView(v),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(children: [
                Icon(icon, size: 22, color: sel ? accent : null),
                const SizedBox(width: 18),
                Expanded(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: sel ? FontWeight.w600 : null))),
              ]),
            ),
          ),
        ),
      );
    }

    Widget spaceChip(String s, String label, Color c) => ChoiceChip(
          label: Text(label),
          selected: space == s,
          selectedColor: c.withValues(alpha: 0.25),
          side: BorderSide(color: space == s ? c : _line),
          onSelected: (_) => onSpace(s),
        );

    return ListView(
      padding: EdgeInsets.only(top: wide ? 8 : 16, bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
          child: Text('Notities',
              style: TextStyle(
                  color: accent, fontSize: 20, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in Store.spaces)
              spaceChip(s, store.spaceName(s), spaceColor(s)),
            spaceChip('all', 'Alles', primary),
          ]),
        ),
        item(Icons.lightbulb_outline, 'Notities', 'notes'),
        if (space != 'private') ...[
          item(Icons.event_note_outlined, 'Bij klussen', 'jobs'),
          item(Icons.history, 'Afgelopen klussen', 'past'),
        ],
        item(Icons.notes, 'Losse notities', 'loose'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
          child: Row(children: [
            const Expanded(
                child: Text('LABELS',
                    style: TextStyle(
                        color: muted, fontSize: 11, letterSpacing: 0.8))),
            InkWell(
              onTap: () => editLabels(context, space),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Text('Bewerken',
                    style: TextStyle(color: muted, fontSize: 12)),
              ),
            ),
          ]),
        ),
        for (final t in tags)
          DragTarget<String>(
            onAcceptWithDetails: (d) => onDropTag(d.data, t),
            builder: (c, cand, _) => Container(
              color: cand.isEmpty ? null : accent.withValues(alpha: 0.15),
              child: item(Icons.label_outline, t, '#$t'),
            ),
          ),
        item(Icons.edit_outlined, 'Labels bewerken', '__edit')
            ._withTap(() => editLabels(context, space)),
        const Divider(color: _line, height: 24),
        item(Icons.archive_outlined, 'Archief', 'archive'),
        item(Icons.delete_outline, 'Prullenbak', 'trash'),
      ],
    );
  }
}

extension on Widget {
  /// Vervangt de tik-actie van een menu-item (voor "Labels bewerken").
  Widget _withTap(VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AbsorbPointer(child: this),
      );
}

/// Kolommen met kaarten van verschillende hoogte (zoals Keep).
class _Masonry extends StatelessWidget {
  final int columns;
  final double width;
  final List<Note> notes;
  final Widget Function(Note n, double width) builder;
  const _Masonry(
      {required this.columns,
      required this.width,
      required this.notes,
      required this.builder});

  double _estimate(Note n, double w) {
    final charsPerLine = (w / 7.5).clamp(10, 200);
    var h = 28.0;
    if (store.noteImages(n.id).isNotEmpty) h += 130;
    if (n.title.trim().isNotEmpty) h += 24;
    var lines = 0.0;
    for (final l in n.text.split('\n').take(10)) {
      lines += (l.length / charsPerLine).ceil().clamp(1, 4);
    }
    h += lines.clamp(0, 10) * 19;
    if (n.tags.isNotEmpty || n.jobKey != null) h += 30;
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final colW = width / columns;
    final cols = List.generate(columns, (_) => <Note>[]);
    final heights = List.filled(columns, 0.0);
    for (final n in notes) {
      var i = 0;
      for (var c = 1; c < columns; c++) {
        if (heights[c] < heights[i] - 1) i = c;
      }
      cols[i].add(n);
      heights[i] += _estimate(n, colW);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final c in cols)
        Expanded(
          child: Column(children: [
            for (final n in c)
              Padding(
                padding: const EdgeInsets.all(5),
                child: builder(n, colW - 10),
              ),
          ]),
        ),
    ]);
  }
}

/// Kaartje van één notitie in het raster of de lijst.
class NoteCard extends StatelessWidget {
  final Note note;
  final bool selected;
  final bool showSpace;
  final VoidCallback onTap;
  const NoteCard(
      {super.key,
      required this.note,
      required this.selected,
      required this.onTap,
      this.showSpace = false});

  @override
  Widget build(BuildContext context) {
    final n = note;
    final primary = Theme.of(context).colorScheme.primary;
    final job = store.job(n.jobKey);
    final images = store.noteImages(n.id);
    final all = n.text.trim().isEmpty ? <String>[] : n.text.trim().split('\n');
    final checkedCount = all.where((l) => l.startsWith('☑')).length;
    final open = all.where((l) => !l.startsWith('☑')).toList();
    final lines = open.take(10).toList();
    final more = open.length > 10;

    Widget line(String l) {
      final checked = l.startsWith('☑');
      final open = l.startsWith('☐');
      if (checked || open) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 6),
            child: Icon(
                checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16,
                color: muted),
          ),
          Expanded(
            child: Text(l.substring(1).trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: checked ? muted : const Color(0xFFD9D7D0),
                    decoration: checked ? TextDecoration.lineThrough : null)),
          ),
        ]);
      }
      return Text(l,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFFD9D7D0)));
    }

    return Material(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: selected ? primary : _line, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (images.isNotEmpty)
            Image.memory(images.first.bytes,
                height: images.length == 1 ? 140 : 110, fit: BoxFit.cover),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (n.title.trim().isNotEmpty || n.pinned || n.lockscreen)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(n.title.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15)),
                            ),
                            if (n.lockscreen)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.lock_outline,
                                    size: 14, color: muted),
                              ),
                            if (n.pinned)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(Icons.push_pin,
                                    size: 14, color: primary),
                              ),
                          ]),
                    ),
                  for (final l in lines)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: line(l)),
                  if (more)
                    const Text('…', style: TextStyle(color: muted)),
                  if (checkedCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                          checkedCount == 1
                              ? '+ 1 afgevinkt item'
                              : '+ $checkedCount afgevinkte items',
                          style: const TextStyle(color: muted, fontSize: 12)),
                    ),
                  if (job != null || n.tags.isNotEmpty || showSpace)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(spacing: 4, runSpacing: 4, children: [
                        if (showSpace && job == null)
                          _Tag(store.spaceName(n.space), spaceColor(n.space)),
                        if (job != null)
                          _Tag(job.title, primary, icon: Icons.event_note),
                        for (final t in n.tags) _Tag(t, null),
                      ]),
                    ),
                  if (n.trashed != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                          'Verwijderd op ${dateShort(n.trashed!)}',
                          style: const TextStyle(color: muted, fontSize: 11)),
                    ),
                ]),
          ),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  const _Tag(this.text, this.color, {this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color?.withValues(alpha: 0.15) ?? const Color(0xFF2A2B2F),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: color ?? const Color(0xFFC9C7C0))),
          ),
        ]),
      );
}
