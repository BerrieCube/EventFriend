import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../platform/open_doc.dart';
import '../store.dart';
import 'docs.dart' show shareDoc;

/// Welke bestanden de ingebouwde viewer kan tonen.
enum ViewKind { pdf, image, text, none }

ViewKind viewKindOf(Doc d) {
  if (d.isLink || d.bytes == null) return ViewKind.none;
  final n = d.name.toLowerCase();
  if (d.isPdf) return ViewKind.pdf;
  if (d.mime.startsWith('image/') ||
      n.endsWith('.jpg') ||
      n.endsWith('.jpeg') ||
      n.endsWith('.png') ||
      n.endsWith('.gif') ||
      n.endsWith('.webp')) {
    return ViewKind.image;
  }
  if (d.mime.startsWith('text/') ||
      n.endsWith('.txt') ||
      n.endsWith('.csv') ||
      n.endsWith('.md')) {
    return ViewKind.text;
  }
  return ViewKind.none;
}

/// Opent [doc] in de ingebouwde viewer. Afbeeldingen uit dezelfde lijst
/// ([siblings]) kun je doorvegen.
void openViewer(BuildContext context, Doc doc, {List<Doc> siblings = const []}) {
  final kind = viewKindOf(doc);
  Widget page;
  switch (kind) {
    case ViewKind.pdf:
      page = PdfViewScreen(doc: doc);
    case ViewKind.image:
      final images =
          siblings.where((d) => viewKindOf(d) == ViewKind.image).toList();
      if (!images.any((d) => d.id == doc.id)) images.insert(0, doc);
      page = ImageViewScreen(
          images: images, initial: images.indexWhere((d) => d.id == doc.id));
    case ViewKind.text:
      page = TextViewScreen(doc: doc);
    case ViewKind.none:
      return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

List<Widget> _actions(BuildContext context, Doc doc) => [
      IconButton(
        tooltip: 'Delen',
        icon: const Icon(Icons.share_outlined),
        onPressed: () => shareDoc(doc),
      ),
      IconButton(
        tooltip: 'Openen in andere app',
        icon: const Icon(Icons.open_in_new),
        onPressed: () async {
          final err = await openBytes(doc.name, doc.mime, doc.bytes!);
          if (err != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Geen app gevonden ($err).')));
          }
        },
      ),
    ];

// ---------------------------------------------------------------- PDF

class PdfViewScreen extends StatefulWidget {
  final Doc doc;
  const PdfViewScreen({super.key, required this.doc});

  @override
  State<PdfViewScreen> createState() => _PdfViewScreenState();
}

class _PdfViewScreenState extends State<PdfViewScreen> {
  final _controller = PdfViewerController();
  late final _searcher = PdfTextSearcher(_controller)..addListener(_update);
  final _query = TextEditingController();
  bool _searching = false;
  int? _page;
  int _pages = 0;

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searcher.removeListener(_update);
    _searcher.dispose();
    _query.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query.clear();
        _searcher.resetTextSearch();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _searcher;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                    hintText: 'Zoeken in document',
                    filled: false,
                    border: InputBorder.none),
                onChanged: (v) => v.trim().isEmpty
                    ? s.resetTextSearch()
                    : s.startTextSearch(v.trim()),
                onSubmitted: (_) => s.goToNextMatch(),
              )
            : Text(widget.doc.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _searching ? 'Zoeken sluiten' : 'Zoeken',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
          if (!_searching) ..._actions(context, widget.doc),
        ],
        bottom: _searching && _query.text.trim().isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        s.matches.isEmpty
                            ? (s.isSearching ? 'Zoeken…' : 'Niets gevonden')
                            : '${(s.currentIndex ?? 0) + 1} van ${s.matches.length}',
                        style: const TextStyle(color: Color(0xFF8A8984)),
                      ),
                    ),
                    IconButton(
                        tooltip: 'Vorige',
                        icon: const Icon(Icons.keyboard_arrow_up),
                        onPressed: s.matches.isEmpty ? null : s.goToPrevMatch),
                    IconButton(
                        tooltip: 'Volgende',
                        icon: const Icon(Icons.keyboard_arrow_down),
                        onPressed: s.matches.isEmpty ? null : s.goToNextMatch),
                  ]),
                ),
              )
            : null,
      ),
      body: Stack(children: [
        PdfViewer.data(
          widget.doc.bytes!,
          sourceName: widget.doc.id,
          controller: _controller,
          params: PdfViewerParams(
            backgroundColor: const Color(0xFF0F1012),
            margin: 8,
            pagePaintCallbacks: [s.pageTextMatchPaintCallback],
            onViewerReady: (doc, c) =>
                setState(() => _pages = doc.pages.length),
            onPageChanged: (p) => setState(() => _page = p),
            errorBannerBuilder: (context, error, stack, ref) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Deze PDF kan niet worden getoond.\n$error',
                    textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
        if (_pages > 0)
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xCC1B1C1F),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('Pagina ${_page ?? 1} van $_pages',
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Afbeeldingen

class ImageViewScreen extends StatefulWidget {
  final List<Doc> images;
  final int initial;
  const ImageViewScreen({super.key, required this.images, required this.initial});

  @override
  State<ImageViewScreen> createState() => _ImageViewScreenState();
}

class _ImageViewScreenState extends State<ImageViewScreen> {
  late final _pager = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  bool _zoomed = false;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.images[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
            widget.images.length > 1
                ? '${_index + 1}/${widget.images.length} · ${doc.name}'
                : doc.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        actions: _actions(context, doc),
      ),
      body: PageView.builder(
        controller: _pager,
        physics: _zoomed
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => _ZoomImage(
          doc: widget.images[i],
          onZoomChanged: (z) {
            if (z != _zoomed) setState(() => _zoomed = z);
          },
        ),
      ),
    );
  }
}

class _ZoomImage extends StatefulWidget {
  final Doc doc;
  final ValueChanged<bool> onZoomChanged;
  const _ZoomImage({required this.doc, required this.onZoomChanged});

  @override
  State<_ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<_ZoomImage> {
  final _t = TransformationController();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Dubbeltik: inzoomen of terug.
      onDoubleTap: () {
        final zoomed = _t.value.getMaxScaleOnAxis() > 1.01;
        _t.value = zoomed
            ? Matrix4.identity()
            : (Matrix4.identity()..scaleByDouble(2.5, 2.5, 1, 1));
        widget.onZoomChanged(!zoomed);
      },
      child: InteractiveViewer(
        transformationController: _t,
        maxScale: 8,
        onInteractionEnd: (_) =>
            widget.onZoomChanged(_t.value.getMaxScaleOnAxis() > 1.01),
        child: Center(
          child: Image.memory(widget.doc.bytes!,
              errorBuilder: (_, __, ___) =>
                  const Text('Deze afbeelding kan niet worden getoond.')),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Tekst

class TextViewScreen extends StatelessWidget {
  final Doc doc;
  const TextViewScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final text = utf8.decode(doc.bytes!, allowMalformed: true);
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: _actions(context, doc),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(text,
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 13, height: 1.4)),
      ),
    );
  }
}
