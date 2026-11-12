import 'dart:math';

import 'package:flutter/material.dart';

import '../format.dart';

/// Tekening van de bridle op schaal: twee punten, twee poten en de apex.
class BridleDiagram extends StatelessWidget {
  final Map<String, double> g;
  const BridleDiagram(this.g, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!g.containsKey('h')) return const SizedBox.shrink();
    return AspectRatio(
      aspectRatio: 2,
      child: CustomPaint(
          painter: _Painter(g, Theme.of(context).colorScheme.primary)),
    );
  }
}

class _Painter extends CustomPainter {
  final Map<String, double> g;
  final Color accent;
  _Painter(this.g, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final d = g['d']!, dh = g['dh']!, x = g['x']!, h = g['h']!;
    // Wereldcoördinaten: y omhoog. A=(0,0), B=(d,dh), P=(x,-h)
    final minY = -h, maxY = max(0.0, dh);
    final w = d, ht = max(maxY - minY, 0.01);
    const pad = 28.0;
    final s = min((size.width - 2 * pad) / w, (size.height - 2 * pad) / ht);
    final ox = (size.width - w * s) / 2;
    final oy = pad + (maxY) * s + ((size.height - 2 * pad) - ht * s) / 2;
    Offset p(double wx, double wy) => Offset(ox + wx * s, oy - wy * s);

    final a = p(0, 0), b = p(d, dh), apex = p(x, -h);
    final beam = Paint()
      ..color = const Color(0xFF555555)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a - const Offset(14, 0), a + const Offset(14, 0), beam);
    canvas.drawLine(b - const Offset(14, 0), b + const Offset(14, 0), beam);

    final leg = Paint()
      ..color = accent
      ..strokeWidth = 2.5;
    canvas.drawLine(a, apex, leg);
    canvas.drawLine(b, apex, leg);
    canvas.drawCircle(apex, 4, Paint()..color = Colors.white);
    canvas.drawLine(apex, apex + const Offset(0, 14),
        Paint()..color = Colors.white70..strokeWidth = 1.5);
    canvas.drawRect(Rect.fromCenter(center: apex + const Offset(0, 20), width: 18, height: 12),
        Paint()..color = const Color(0xFF3A3B3F));

    void label(String t, Offset at, {Color c = Colors.white}) {
      final tp = TextPainter(
          text: TextSpan(text: t, style: TextStyle(color: c, fontSize: 12)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    label('A', a + const Offset(0, -12));
    label('B', b + const Offset(0, -12));
    label('${nf(g['angle']!, 1)}°', apex + const Offset(26, -10), c: accent);
  }

  @override
  bool shouldRepaint(covariant _Painter old) => old.g != g;
}
