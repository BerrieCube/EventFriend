/// Telefoonfuncties buiten de app (alleen Android):
/// - notities als vaste melding op het vergrendelscherm
/// - widgets op het startscherm (volgende klus, notitie)
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'format.dart';
import 'store.dart';

class DeviceIntegration {
  final _notifications = FlutterLocalNotificationsPlugin();
  final _shown = <int>{};
  final _scheduled = <int>{};
  Timer? _debounce;
  bool _ready = false;

  /// Waar een aangetikte melding naartoe moet: 'note:<id>' of 'job:<key>'.
  /// Het startscherm luistert hierop en opent de notitie of klus.
  final openRequest = ValueNotifier<String?>(null);

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!supported) return;
    try {
      tzdata.initializeTimeZones();
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) => openRequest.value = r.payload,
      );
      // App gestart door op een melding te tikken?
      final launch = await _notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        openRequest.value = launch!.notificationResponse?.payload;
      }
      // Na een herstart van de telefoon zijn meldingen weg: opnieuw tonen.
      await _notifications.cancelAll();
      _ready = true;
    } catch (e) {
      debugPrint('Meldingen niet beschikbaar: $e');
    }
    store.addListener(_schedule);
    await refresh();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), refresh);
  }

  /// Vraagt toestemming voor meldingen (Android 13+). Geeft false bij weigering.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> refresh() async {
    if (!supported) return;
    await _refreshLockscreen();
    await _refreshReminders();
    await _refreshWidgets();
  }

  int _idFor(String noteId) => noteId.hashCode & 0x7fffffff;

  Future<void> _refreshLockscreen() async {
    if (!_ready) return;
    final notes = store.notes.where((n) => n.lockscreen).toList();
    final now = <int>{};
    for (final n in notes) {
      final id = _idFor(n.id);
      now.add(id);
      final title = n.title.trim().isNotEmpty
          ? n.title.trim()
          : (n.jobTitle ?? 'Notitie');
      await _notifications.show(
        id: id,
        title: title,
        body: n.text,
        payload: 'note:${n.id}',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'lockscreen_notes',
            'Notities op vergrendelscherm',
            channelDescription:
                'Notities die je zelf op het vergrendelscherm hebt vastgezet',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: false,
            playSound: false,
            enableVibration: false,
            visibility: NotificationVisibility.public,
            category: AndroidNotificationCategory.reminder,
            styleInformation: BigTextStyleInformation(n.text,
                contentTitle: title),
          ),
        ),
      );
    }
    for (final id in _shown.difference(now)) {
      await _notifications.cancel(id: id);
    }
    _shown
      ..clear()
      ..addAll(now);
  }

  /// Calltime-herinneringen voor de klussen van de komende 14 dagen.
  Future<void> _refreshReminders() async {
    if (!_ready) return;
    final before = store.reminderMinutes;
    final now = DateTime.now();
    final want = <int, (Job, DateTime)>{};
    if (before > 0) {
      for (final j in store.planningJobs) {
        final at = j.start.subtract(Duration(minutes: before));
        if (at.isAfter(now) && at.isBefore(now.add(const Duration(days: 14)))) {
          want[('rem|${j.key}|${j.start}|$before').hashCode & 0x7fffffff] = (j, at);
        }
      }
    }
    for (final id in _scheduled.difference(want.keys.toSet())) {
      await _notifications.cancel(id: id);
    }
    for (final e in want.entries) {
      if (_scheduled.contains(e.key)) continue;
      final (j, at) = e.value;
      final client = store.clientName(j);
      Future<void> schedule(AndroidScheduleMode mode) =>
          _notifications.zonedSchedule(
            id: e.key,
            title: 'Om ${hm(j.start)}: ${j.title}',
            body: [client, if (j.location.isNotEmpty) j.location].join(' · '),
            payload: 'job:${j.key}',
            scheduledDate: tz.TZDateTime.from(at, tz.UTC),
            androidScheduleMode: mode,
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'calltime',
                'Calltime-herinneringen',
                channelDescription: 'Melding vóór de start van een klus',
                importance: Importance.high,
                priority: Priority.high,
                category: AndroidNotificationCategory.reminder,
              ),
            ),
          );
      try {
        await schedule(AndroidScheduleMode.exactAllowWhileIdle);
      } catch (_) {
        // Geen toestemming voor exacte wekkers: iets minder precies.
        await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      }
      _scheduled.add(e.key);
    }
    _scheduled.removeWhere((id) => !want.containsKey(id));
  }

  Future<void> _refreshWidgets() async {
    try {
      // Volgende klus: lopende of eerstvolgende.
      final t = DateTime.now();
      final next = store.planningJobs.where((j) => j.end.isAfter(t)).firstOrNull;
      if (next == null) {
        await HomeWidget.saveWidgetData<String>('next_title', 'Geen klussen gepland');
        await HomeWidget.saveWidgetData<String>('next_time', '');
        await HomeWidget.saveWidgetData<String>('next_loc', '');
      } else {
        final when = sameDay(next.start, t)
            ? 'Vandaag ${hm(next.start)}–${hm(next.end)}'
            : '${dateShort(next.start)} · ${hm(next.start)}–${hm(next.end)}';
        await HomeWidget.saveWidgetData<String>('next_title', next.title);
        await HomeWidget.saveWidgetData<String>('next_time', when);
        await HomeWidget.saveWidgetData<String>('next_loc', next.location);
      }
      await HomeWidget.updateWidget(
          qualifiedAndroidName: 'nl.eventfriend.eventfriend.NextJobWidget');

      final note = store.notes.where((n) => n.widget).firstOrNull;
      await HomeWidget.saveWidgetData<String>(
          'note_title',
          note == null
              ? 'Notitie'
              : (note.title.trim().isNotEmpty
                  ? note.title.trim()
                  : (note.jobTitle ?? 'Notitie')));
      await HomeWidget.saveWidgetData<String>(
          'note_text',
          note?.text ??
              'Open een notitie in EventFriend en zet "Op widget" aan.');
      await HomeWidget.updateWidget(
          qualifiedAndroidName: 'nl.eventfriend.eventfriend.NoteWidget');
    } catch (e) {
      debugPrint('Widgets bijwerken mislukt: $e');
    }
  }
}

final device = DeviceIntegration();
