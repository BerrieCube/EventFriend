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
DateTime weekStart(DateTime d) =>
    dayStart(d).subtract(Duration(days: d.weekday - 1));

/// ISO-weeknummer.
int isoWeek(DateTime d) {
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final jan1 = DateTime(thursday.year, 1, 1);
  return ((thursday.difference(jan1).inDays) ~/ 7) + 1;
}
