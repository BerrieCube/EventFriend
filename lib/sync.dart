/// Synchronisatie met Supabase: telefoon en webversie delen dezelfde
/// agenda's, eigen klussen, notities, foto's en uren.
///
/// Werkwijze: elke lokale wijziging wordt als "dirty" bewaard en bij de
/// volgende sync geüpload (laatste wijziging wint). Daarna worden alle
/// wijzigingen van de server sinds de vorige keer opgehaald.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'store.dart';

class SyncService extends ChangeNotifier {
  bool _ready = false;
  bool busy = false;
  String? lastError;
  Timer? _debounce;

  SupabaseClient get _db => Supabase.instance.client;
  User? get user => _ready ? _db.auth.currentUser : null;
  bool get loggedIn => user != null;

  Future<void> init() async {
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
      _ready = true;
    } catch (e) {
      lastError = 'Supabase niet bereikbaar: $e';
      return;
    }
    store.onLocalChange = _schedule;
    _db.auth.onAuthStateChange.listen((_) {
      _wireIcal();
      notifyListeners();
    });
    _wireIcal();
  }

  void _wireIcal() {
    store.remoteIcalFetch = loggedIn ? _fetchIcal : null;
  }

  Future<String> _fetchIcal(String url) async {
    final res = await _db.functions.invoke('ical', body: {'url': url});
    final data = res.data;
    if (data is String) return data;
    throw Exception('Onverwacht antwoord van de agenda-functie');
  }

  void _schedule() {
    if (!loggedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), run);
  }

  Future<String?> signIn(String email, String password) async {
    try {
      await _db.auth.signInWithPassword(email: email, password: password);
      await _afterLogin();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<String?> signUp(String email, String password) async {
    try {
      final r = await _db.auth.signUp(email: email, password: password);
      if (r.session == null) {
        return 'Account aangemaakt. Bevestig via de mail en log daarna in.';
      }
      await _afterLogin();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<void> _afterLogin() async {
    await store.setLastPull(null);
    await store.markAllDirty();
    notifyListeners();
    await run();
    await store.syncAll();
  }

  Future<void> signOut() async {
    await _db.auth.signOut();
    notifyListeners();
  }

  /// Volledige sync: eerst uploaden, dan ophalen.
  Future<void> run() async {
    if (!loggedIn || busy) return;
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      await _push();
      final newCalendars = await _pull();
      await store.setLastSyncTime(DateTime.now());
      store.refresh();
      for (final id in newCalendars) {
        final c = store.calendar(id);
        if (c != null) await store.syncCalendar(c);
      }
    } catch (e) {
      lastError = 'Synchroniseren mislukt: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _push() async {
    final uid = user!.id;
    final dirty = store.dirty;
    for (final entry in dirty.entries) {
      final sep = entry.key.indexOf('|');
      final kind = entry.key.substring(0, sep);
      final id = entry.key.substring(sep + 1);
      final data = store.localRecord(kind, id);
      if (kind == 'photo') {
        final path = '$uid/$id.jpg';
        if (data != null) {
          final bytes = store.photoBytes(id);
          if (bytes != null) {
            await _db.storage.from('photos').uploadBinary(path, bytes,
                fileOptions:
                    const FileOptions(upsert: true, contentType: 'image/jpeg'));
          }
        } else {
          try {
            await _db.storage.from('photos').remove([path]);
          } catch (_) {}
        }
      }
      await _db.from('records').upsert({
        'kind': kind,
        'id': id,
        'data': data,
        'deleted': data == null,
        'updated_at': entry.value,
      });
      await store.clearDirty(entry.key, entry.value);
    }
  }

  /// Geeft de id's terug van agenda's die nieuw binnenkwamen.
  Future<List<String>> _pull() async {
    final uid = user!.id;
    final since = store.lastPull;
    var q = _db.from('records').select();
    if (since != null) q = q.gt('server_updated_at', since);
    final rows = await q.order('server_updated_at');
    final dirty = store.dirty;
    final newCalendars = <String>[];
    String? newest = since;

    for (final r in rows) {
      final kind = r['kind'] as String;
      final id = r['id'] as String;
      newest = r['server_updated_at'] as String;
      final local = dirty['$kind|$id'];
      if (local != null &&
          DateTime.parse(local).isAfter(DateTime.parse(r['updated_at']))) {
        continue; // lokale wijziging is nieuwer en wordt bij de volgende push verstuurd
      }
      final deleted = r['deleted'] == true;
      final data = deleted ? null : Map<String, dynamic>.from(r['data'] as Map);
      if (kind == 'calendar' && data != null && !store.hasLocal(kind, id)) {
        newCalendars.add(id);
      }
      Uint8List? bytes;
      if (kind == 'photo' && data != null && store.photoBytes(id) == null) {
        try {
          bytes = await _db.storage.from('photos').download('$uid/$id.jpg');
        } catch (_) {
          continue; // foto nog niet beschikbaar; volgende keer opnieuw
        }
      }
      await store.applyRemote(kind, id, data, bytes: bytes);
    }
    await store.setLastPull(newest);
    return newCalendars;
  }
}

final sync = SyncService();
