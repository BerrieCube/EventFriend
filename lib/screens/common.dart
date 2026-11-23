import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pdf_theme.dart' show splitLinks;
import '../route.dart' show geocode;
import '../store.dart';
import 'settings.dart';

const muted = Color(0xFF8A8984);

/// Tandwiel rechtsboven: naar de agenda-instellingen.
class SettingsAction extends StatelessWidget {
  const SettingsAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Instellingen',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen())),
      );
}

/// Herbouwt bij elke wijziging in de opslag.
class StoreBuilder extends StatelessWidget {
  final WidgetBuilder builder;
  const StoreBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: store, builder: (c, _) => builder(c));
}

/// Laat kiezen met welke app je navigeert.
Future<void> openRoute(BuildContext context, String location) async {
  final q = Uri.encodeComponent(location);
  final options = <(IconData, String, Uri)>[
    (Icons.map_outlined, 'Google Maps',
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$q')),
    (Icons.navigation_outlined, 'Waze', Uri()), // zie _openWaze
    if (!kIsWeb)
      (Icons.apps, 'Andere app…', Uri.parse('geo:0,0?q=$q')),
  ];
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(location,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted)),
        ),
        for (final o in options)
          ListTile(
            leading: Icon(o.$1),
            title: Text(o.$2),
            onTap: () {
              Navigator.pop(c);
              if (o.$2 == 'Waze') {
                _openWaze(location);
              } else {
                launchUrl(o.$3, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ListTile(
          leading: const Icon(Icons.copy),
          title: const Text('Adres kopiëren'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: location));
            Navigator.pop(c);
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// Waze navigeert betrouwbaar naar coördinaten; een adres als zoekterm
/// opent vaak alleen de zoekbalk. Daarom eerst het adres opzoeken.
Future<void> _openWaze(String location) async {
  final q = Uri.encodeComponent(location);
  String params;
  try {
    final (lat, lon) =
        await geocode(location).timeout(const Duration(seconds: 6));
    params = 'll=$lat,$lon&navigate=yes';
  } catch (_) {
    params = 'q=$q&navigate=yes';
  }
  if (!kIsWeb) {
    try {
      if (await launchUrl(Uri.parse('waze://?$params'),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
  }
  await launchUrl(Uri.parse('https://waze.com/ul?$params'),
      mode: LaunchMode.externalApplication);
}

Future<void> callNumber(String number) =>
    launchUrl(Uri(scheme: 'tel', path: number));

Future<bool> confirm(BuildContext context, String title, String body,
    {String ok = 'Verwijderen'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuleren')),
        FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600))),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const EmptyHint(
      {super.key,
      required this.icon,
      required this.title,
      required this.body,
      this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: muted),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

/// Naam van de opdrachtgever, klein en duidelijk boven de klusnaam.
class ClientLabel extends StatelessWidget {
  final Job job;
  final double size;
  const ClientLabel(this.job, {super.key, this.size = 12});

  @override
  Widget build(BuildContext context) => Text(
        store.clientName(job),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: size,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      );
}

/// Kaarten in kolommen op een breed scherm, onder elkaar op de telefoon.
class TileGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  const TileGrid({super.key, required this.children, this.minTileWidth = 320});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = (box.maxWidth / minTileWidth).floor().clamp(1, 4);
        if (cols == 1) return Column(children: children);
        const gap = 8.0;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      });
}


/// Selecteerbare tekst waarin webadressen aantikbaar zijn.
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const LinkText(this.text, {super.key, this.style});

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final link = TextStyle(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline);
    return SelectableText.rich(TextSpan(style: widget.style, children: [
      for (final p in splitLinks(widget.text))
        if (p.$2 == null)
          TextSpan(text: p.$1)
        else
          TextSpan(
            text: p.$1,
            style: link,
            recognizer: (TapGestureRecognizer()
              ..onTap = () => launchUrl(Uri.parse(p.$2!),
                  mode: LaunchMode.externalApplication))
              .._register(_recognizers),
          ),
    ]));
  }
}

extension on TapGestureRecognizer {
  void _register(List<TapGestureRecognizer> l) => l.add(this);
}
