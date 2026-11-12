import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../format.dart';

/// Fullscreen klok HH:MM:SS. Draait mee met de telefoon, scherm blijft aan.
/// Tik om terug te gaan.
class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final n = DateTime.now();
      if (n.second != _now.second) setState(() => _now = n);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = '${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}';
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FittedBox(
                fit: BoxFit.contain,
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 200,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
