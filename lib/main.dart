import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;

import 'screens/dashboard.dart';
import 'screens/hours.dart';
import 'screens/job_detail.dart';
import 'screens/jobs.dart';
import 'screens/notes.dart';
import 'screens/today.dart';
import 'screens/tools.dart';
import 'store.dart';
import 'device.dart';
import 'sync.dart';

const amber = Color(0xFFEF9F27);
const bg = Color(0xFF0F1012);
const card = Color(0xFF1B1C1F);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.init();
  await sync.init();
  unawaited(device.init());
  runApp(const EventFriendApp());
  // Op de achtergrond: gegevens synchroniseren en agenda's verversen.
  sync.run().whenComplete(() async {
    await store.cleanupExpiredDocs();
    await store.cleanupTrash();
    await store.syncAll();
  });
}

class EventFriendApp extends StatelessWidget {
  const EventFriendApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: amber,
      brightness: Brightness.dark,
    ).copyWith(
      primary: amber,
      onPrimary: const Color(0xFF412402),
      surface: bg,
      surfaceContainerLowest: bg,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: const Color(0xFF232428),
    );
    return MaterialApp(
      title: 'EventFriend',
      debugShowCheckedModeBanner: false,
      locale: const Locale('nl'),
      supportedLocales: const [Locale('nl'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: bg,
        cardTheme: const CardThemeData(
          color: card,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
        appBarTheme: const AppBarTheme(
            backgroundColor: bg, surfaceTintColor: Colors.transparent),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF141518),
          indicatorColor: amber.withValues(alpha: 0.18),
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected)
                  ? amber
                  : const Color(0xFF8A8984))),
          labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 12,
              color: s.contains(WidgetState.selected)
                  ? amber
                  : const Color(0xFF8A8984))),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF232428),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide.none),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String? _tabId;

  /// (id, label, icoon) van alle tabs.
  static const _meta = <String, (String, IconData)>{
    'dashboard': ('Dashboard', Icons.dashboard_outlined),
    'today': ('Vandaag', Icons.home_outlined),
    'jobs': ('Klussen', Icons.calendar_month_outlined),
    'hours': ('Uren', Icons.schedule),
    'notes': ('Notities', Icons.sticky_note_2_outlined),
    'tools': ('Tools', Icons.handyman_outlined),
  };

  @override
  void initState() {
    super.initState();
    device.openRequest.addListener(_open);
    store.addListener(_onStore);
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    device.openRequest.removeListener(_open);
    store.removeListener(_onStore);
    super.dispose();
  }

  /// Tabs kunnen in de instellingen aan/uit worden gezet.
  void _onStore() {
    if (mounted) setState(() {});
  }

  void _go(String id) {
    if (store.enabledTabs.contains(id)) {
      setState(() => _tabId = id);
    } else if (id == 'jobs') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const JobsScreen()));
    } else if (id == 'notes') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const NotesScreen()));
    }
  }

  /// Aangetikte melding: open de notitie of klus.
  void _open() {
    final p = device.openRequest.value;
    if (p == null || !mounted) return;
    device.openRequest.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (p.startsWith('note:')) {
      final id = p.substring(5);
      final n = store.notes.where((n) => n.id == id).firstOrNull;
      if (n == null) return;
      if (store.enabledTabs.contains('notes')) setState(() => _tabId = 'notes');
      editNote(context, note: n, job: store.job(n.jobKey));
    } else if (p.startsWith('job:')) {
      openJob(context, p.substring(4));
    }
  }

  Widget _page(String id) => switch (id) {
        'dashboard' => const DashboardScreen(),
        'today' => TodayScreen(onOpenJobs: () => _go('jobs')),
        'jobs' => const JobsScreen(),
        'hours' => const HoursScreen(),
        'notes' => const NotesScreen(),
        _ => const ToolsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final tabs = store.enabledTabs;
    final id = tabs.contains(_tabId) ? _tabId! : tabs.first;
    final index = tabs.indexOf(id);
    final pages = [for (final t in tabs) KeyedSubtree(key: ValueKey(t), child: _page(t))];
    final body = IndexedStack(index: index, children: pages);
    void select(int i) => setState(() => _tabId = tabs[i]);

    final wide = MediaQuery.sizeOf(context).width >= 800;
    if (wide) {
      // Laptop/tablet: navigatie aan de zijkant.
      final extended = MediaQuery.sizeOf(context).width >= 1100;
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            extended: extended,
            backgroundColor: const Color(0xFF141518),
            indicatorColor: amber.withValues(alpha: 0.18),
            selectedIconTheme: const IconThemeData(color: amber),
            selectedLabelTextStyle: const TextStyle(color: amber),
            unselectedLabelTextStyle: const TextStyle(color: Color(0xFF8A8984)),
            unselectedIconTheme: const IconThemeData(color: Color(0xFF8A8984)),
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: extended
                  ? const Text('EventFriend',
                      style: TextStyle(
                          color: amber,
                          fontSize: 18,
                          fontWeight: FontWeight.w600))
                  : const Icon(Icons.bolt, color: amber),
            ),
            onDestinationSelected: select,
            destinations: [
              for (final t in tabs)
                NavigationRailDestination(
                    icon: Icon(_meta[t]!.$2), label: Text(_meta[t]!.$1)),
            ],
          ),
          const VerticalDivider(width: 1, color: Color(0xFF232428)),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: select,
              labelBehavior: tabs.length > 5
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : null,
              destinations: [
                for (final t in tabs)
                  NavigationDestination(
                      icon: Icon(_meta[t]!.$2), label: _meta[t]!.$1),
              ],
            ),
    );
  }
}
