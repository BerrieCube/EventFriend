/// Afstand over de weg tussen twee adressen, via OpenStreetMap
/// (Nominatim voor het adres, OSRM voor de route). Gratis, geen sleutel nodig.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

// In de browser stuurt die zelf de herkomst mee; een eigen User-Agent kan daar niet.
const Map<String, String> _headers =
    kIsWeb ? {} : {'User-Agent': 'EventFriend/0.1 (persoonlijke app)'};

/// Coördinaten (lat, lon) van een adres.
Future<(double, double)> geocode(String address) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search',
      {'format': 'json', 'limit': '1', 'q': address});
  final res = await http
      .get(uri, headers: _headers)
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) {
    throw Exception('Adres zoeken mislukt (status ${res.statusCode})');
  }
  final l = jsonDecode(res.body) as List;
  if (l.isEmpty) throw Exception('Adres niet gevonden: $address');
  final m = l.first as Map;
  return (double.parse(m['lat']), double.parse(m['lon']));
}

/// Enkele reis in kilometers over de weg.
Future<double> roadDistanceKm(String from, String to) async {
  final a = await geocode(from);
  final b = await geocode(to);
  final uri = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
      '${a.$2},${a.$1};${b.$2},${b.$1}?overview=false');
  final res = await http
      .get(uri, headers: _headers)
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) {
    throw Exception('Route berekenen mislukt (status ${res.statusCode})');
  }
  final routes = (jsonDecode(res.body) as Map)['routes'] as List?;
  if (routes == null || routes.isEmpty) throw Exception('Geen route gevonden');
  return ((routes.first as Map)['distance'] as num) / 1000;
}
