/// Bridle-berekening (2D statica). Puur rekenwerk, zonder Flutter.
library;

import 'dart:math';

class BridleResult {
  final double la, lb; // pootlengtes (m)
  final double ta, tb; // kracht per poot (kg)
  final double angle; // hoek tussen poten (graden)
  final double angleA, angleB; // hoek poot t.o.v. verticaal (graden)
  final double horizontal; // horizontale trekkracht (kg)
  BridleResult(this.la, this.lb, this.ta, this.tb, this.angle, this.angleA,
      this.angleB, this.horizontal);
}

/// A ligt op (0, 0), B op (d, dh). De apex ligt op (x, -h): x meter
/// horizontaal vanaf A en h meter onder A. Last w hangt verticaal aan de apex.
BridleResult bridle(
    {required double d,
    required double dh,
    required double x,
    required double h,
    required double w}) {
  final la = sqrt(x * x + h * h);
  final hb = h + dh; // apex onder B
  final lb = sqrt((d - x) * (d - x) + hb * hb);
  final denom = x * hb + (d - x) * h;
  final ta = w * (d - x) * la / denom;
  final tb = w * x * lb / denom;
  // Eenheidsvectoren van apex naar A en naar B.
  final uax = -x / la, uay = h / la;
  final ubx = (d - x) / lb, uby = hb / lb;
  final dot = (uax * ubx + uay * uby).clamp(-1.0, 1.0);
  final angle = acos(dot) * 180 / pi;
  final angleA = atan2(x, h) * 180 / pi;
  final angleB = atan2(d - x, hb) * 180 / pi;
  return BridleResult(la, lb, ta, tb, angle, angleA, angleB, ta * x / la);
}

/// Zoekt de apex-diepte h (onder A) waarbij de hoek tussen de poten
/// gelijk is aan [angleDeg]. Bisectie: hoe dieper de apex, hoe kleiner de hoek.
double bridleDepthForAngle(
    {required double d,
    required double dh,
    required double x,
    required double angleDeg}) {
  double angleAt(double h) => bridle(d: d, dh: dh, x: x, h: h, w: 1).angle;
  var lo = max(0.0, -dh) + 1e-9;
  var hi = 10000.0;
  for (var i = 0; i < 200; i++) {
    final mid = (lo + hi) / 2;
    if (angleAt(mid) > angleDeg) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}
