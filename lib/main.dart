import 'package:flutter/material.dart';

import 'screens/hours.dart';
import 'screens/jobs.dart';
import 'screens/notes.dart';
import 'screens/today.dart';
import 'screens/tools.dart';
import 'store.dart';

const amber = Color(0xFFEF9F27);
const bg = Color(0xFF0F1012);
const card = Color(0xFF1B1C1F);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.init();
  runApp(const EventFriendApp());
  // Agenda's op de achtergrond verversen bij het opstarten.
  store.syncAll();
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
