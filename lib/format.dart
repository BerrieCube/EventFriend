/// Nederlandse opmaak van getallen en datums, zonder extra packages.
library;

const _days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
const _daysLong = [
  'maandag',
  'dinsdag',
  'woensdag',
  'donderdag',
  'vrijdag',
  'zaterdag',
  'zondag'
];
const _months = [
  'jan',
  'feb',
  'mrt',
  'apr',
  'mei',
  'jun',
  'jul',
  'aug',
  'sep',
  'okt',
  'nov',
  'dec'
];

/// Getal met vast aantal decimalen en een komma.
String nf(double v, [int decimals = 2]) {
  if (v.isNaN || v.isInfinite) return '–';
  return v.toStringAsFixed(decimals).replaceAll('.', ',');
}

/// Leest "1,5" en "1.5" als 1.5. Geeft null bij ongeldige invoer.
double? parseNum(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String two(int n) => n.toString().padLeft(2, '0');

String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String dateShort(DateTime d) =>
    '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String dateLong(DateTime d) =>
    '${_daysLong[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';

String duration(Duration d) {
  final m = d.inMinutes;
  return '${m ~/ 60}u ${two(m % 60)}m';
}

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Maandag van de week waarin [d] valt.
/// Rekent in kalenderdagen (niet in 24 uur), zodat zomer-/wintertijd
/// de datum niet verschuift.
DateTime weekStart(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// ISO-weeknummer.
int isoWeek(DateTime d) {
  final thursday = DateTime.utc(d.year, d.month, d.day + 4 - d.weekday);
  final jan1 = DateTime.utc(thursday.year, 1, 1);
  return ((thursday.difference(jan1).inDays) ~/ 7) + 1;
}

/// Bedrag in euro's: € 12,50
String euro(double v) => '€ ${nf(v, 2)}';

const _monthsLong = [
  'januari', 'februari', 'maart', 'april', 'mei', 'juni', 'juli',
  'augustus', 'september', 'oktober', 'november', 'december'
];

/// "november 2026"
String monthYear(DateTime d) => '${_monthsLong[d.month - 1]} ${d.year}';

/// Korte dagnamen, maandag eerst.
const weekdayShort = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
