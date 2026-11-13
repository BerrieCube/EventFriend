import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;

import 'screens/hours.dart';
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
      // Op een groot scherm (laptop) niet over de hele breedte uitrekken.
      builder: (context, child) => ColoredBox(
        color: const Color(0xFF0A0B0C),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: child,
          ),
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
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayScreen(onOpenJobs: () => setState(() => _tab = 1)),
      const JobsScreen(),
      const HoursScreen(),
      const NotesScreen(),
      const ToolsScreen(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 800;
    if (wide) {
      // Laptop/tablet: navigatie aan de zijkant, inhoud niet te breed.
      final extended = MediaQuery.sizeOf(context).width >= 1100;
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
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
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationRailDestination(
                  icon: Icon(Icons.home_outlined), label: Text('Vandaag')),
              NavigationRailDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: Text('Klussen')),
              NavigationRailDestination(
                  icon: Icon(Icons.schedule), label: Text('Uren')),
              NavigationRailDestination(
                  icon: Icon(Icons.sticky_note_2_outlined),
                  label: Text('Notities')),
              NavigationRailDestination(
                  icon: Icon(Icons.handyman_outlined), label: Text('Tools')),
            ],
          ),
          const VerticalDivider(width: 1, color: Color(0xFF232428)),
          Expanded(child: IndexedStack(index: _tab, children: pages)),
        ]),
      );
    }
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Vandaag'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined), label: 'Klussen'),
          NavigationDestination(icon: Icon(Icons.schedule), label: 'Uren'),
          NavigationDestination(
              icon: Icon(Icons.sticky_note_2_outlined), label: 'Notities'),
          NavigationDestination(
              icon: Icon(Icons.handyman_outlined), label: 'Tools'),
        ],
      ),
    );
  }
}
