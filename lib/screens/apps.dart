
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:url_launcher/url_launcher.dart';

import '../calc/defs.dart' show categoryOrder;
import '../store.dart';
import 'common.dart';

/// Onderdelen waar je app- en link-tegels onder kunt zetten.
const appSections = ['Algemeen', ...categoryOrder];

bool get canPickApps =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

final _iconCache = <String, Future<Uint8List?>>{};

Future<Uint8List?> _icon(String package) => _iconCache.putIfAbsent(
    package,
    () => InstalledApps.getAppInfo(package)
        .then((a) => a?.icon)
        .catchError((_) => null));

/// Zichtbare tegels in een onderdeel. Apps alleen op Android.
List<AppTile> visibleApps(String section) =>
    store.appsIn(section).where((a) => !a.isApp || canPickApps).toList();

Future<void> launchTile(BuildContext context, AppTile a) async {
  bool ok;
  if (a.isApp) {
    ok = await InstalledApps.startApp(a.package!) ?? false;
  } else {
    ok = await launchUrl(Uri.parse(a.url!), mode: LaunchMode.externalApplication);
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(a.isApp
            ? '${a.name} is niet (meer) geïnstalleerd.'
            : 'Kan de link niet openen.')));
  }
}

class AppTileCard extends StatelessWidget {
  final AppTile tile;
  const AppTileCard({super.key, required this.tile});

  @override
  Widget build(BuildContext context) {
    final a = tile;
    final primary = Theme.of(context).colorScheme.primary;
    Widget leading = Icon(
        a.url != null && a.url!.contains('spotify')
            ? Icons.queue_music
            : Icons.link,
        color: primary);
    if (a.isApp) {
      leading = FutureBuilder<Uint8List?>(
        future: _icon(a.package!),
        builder: (c, s) => s.data == null
            ? Icon(Icons.apps, color: primary)
            : Image.memory(s.data!, width: 32, height: 32),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: SizedBox(width: 32, child: Center(child: leading)),
          title: Text(a.name),
          subtitle: Text(a.isApp ? 'App' : (a.url ?? ''),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => launchTile(context, a),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') await editTile(context, a);
              if (v == 'up' || v == 'down') _move(a, v == 'up' ? -1 : 1);
              if (v == 'del' &&
                  await confirm(context, 'Tegel verwijderen?',
                      '"${a.name}" verdwijnt uit Tools.')) {
                store.deleteApp(a.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Wijzigen / verplaatsen')),
              PopupMenuItem(value: 'up', child: Text('Omhoog')),
              PopupMenuItem(value: 'down', child: Text('Omlaag')),
              PopupMenuItem(value: 'del', child: Text('Verwijderen')),
            ],
          ),
        ),
      ),
    );
  }

  void _move(AppTile a, int dir) {
    final list = store.appsIn(a.section);
    final i = list.indexWhere((x) => x.id == a.id);
    final j = i + dir;
    if (j < 0 || j >= list.length) return;
    final other = list[j];
    final o = a.order;
    a.order = other.order;
    other.order = o;
    if (a.order == other.order) a.order += dir * 0.5;
    store.saveApp(a);
    store.saveApp(other);
  }
}

/// Keuzemenu: app kiezen (Android) of link toevoegen.
Future<void> addAppOrLink(BuildContext context, {String section = 'Algemeen'}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (canPickApps)
          ListTile(
            leading: const Icon(Icons.apps),
            title: const Text('App van je telefoon'),
            subtitle: const Text('Bijvoorbeeld Spotify, Teams of je lichtapp'),
            onTap: () async {
              Navigator.pop(c);
              final app = await Navigator.of(context).push<AppInfo>(
                  MaterialPageRoute(builder: (_) => const _AppPicker()));
              if (app == null || !context.mounted) return;
              await editTile(
                  context,
                  AppTile(
                      id: newId(),
                      type: 'app',
                      name: app.name,
                      package: app.packageName,
                      section: section),
                  isNew: true);
            },
          ),
        ListTile(
          leading: const Icon(Icons.add_link),
          title: const Text('Link'),
          subtitle: const Text('Spotify-playlist, website, Drive-map, …'),
          onTap: () {
            Navigator.pop(c);
            editTile(context,
                AppTile(id: newId(), type: 'link', name: '', section: section),
                isNew: true);
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// Naam, link en onderdeel instellen.
Future<void> editTile(BuildContext context, AppTile a, {bool isNew = false}) async {
  final name = TextEditingController(text: a.name);
  final url = TextEditingController(text: a.url ?? '');
  var section = a.section;
  String? error;
  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(isNew
            ? (a.isApp ? 'App toevoegen' : 'Link toevoegen')
            : 'Tegel wijzigen'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                decoration: InputDecoration(
                    labelText: 'Naam',
                    hintText: a.isApp ? null : 'Opbouw-playlist')),
            if (!a.isApp) ...[
              const SizedBox(height: 8),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                    labelText: 'Link',
                    hintText: 'https://open.spotify.com/playlist/…'),
              ),
              const SizedBox(height: 4),
              const Text(
                  'Spotify: open de playlist → Delen → Link kopiëren, en plak hem hier.',
                  style: TextStyle(color: muted, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: section,
              decoration: const InputDecoration(labelText: 'Onder onderdeel'),
              items: [
                for (final s in appSections)
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) => setS(() => section = v ?? section),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error)),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) {
                setS(() => error = 'Geef de tegel een naam.');
                return;
              }
              if (!a.isApp) {
                var u = url.text.trim();
                if (u.isEmpty) {
                  setS(() => error = 'Plak een link.');
                  return;
                }
                if (!u.contains(':')) u = 'https://$u';
                a.url = u;
              }
              a.name = name.text.trim();
              if (section != a.section || isNew) {
                final existing = store.appsIn(section);
                a.order = existing.isEmpty ? 0 : existing.last.order + 1;
              }
              a.section = section;
              store.saveApp(a);
              Navigator.pop(c);
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    ),
  );
}

class _AppPicker extends StatefulWidget {
  const _AppPicker();

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  late final Future<List<AppInfo>> _apps = InstalledApps.getInstalledApps(
          excludeSystemApps: false, withIcon: true)
      .then((l) => l
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kies een app')),
      body: FutureBuilder<List<AppInfo>>(
        future: _apps,
        builder: (context, s) {
          if (s.hasError) {
            return Center(child: Text('Apps ophalen mislukt: ${s.error}'));
          }
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final q = _q.toLowerCase();
          final list =
              s.data!.where((a) => a.name.toLowerCase().contains(q)).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Zoeken'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final a = list[i];
                  return ListTile(
                    leading: a.icon == null
                        ? const Icon(Icons.apps)
                        : Image.memory(a.icon!, width: 36, height: 36),
                    title: Text(a.name),
                    onTap: () => Navigator.pop(context, a),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}
