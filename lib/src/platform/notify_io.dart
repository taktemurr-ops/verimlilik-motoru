/// Mobil bildirimler. Zamanlar UTC olarak verilir; böylece yaz saati
/// geçişleri yanlış saate kaymaz (her alarm ayrı ayrı planlanır).
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Notify {
  static final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get supported => true;

  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _p.initialize(settings);
      _ready = true;
    } catch (_) {/* bildirim olmadan da çalışır */}
  }

  static Future<bool> requestPermission() async {
    await init();
    try {
      final a = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (a != null) return await a.requestNotificationsPermission() ?? false;
      final i = _p.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (i != null) return await i.requestPermissions(alert: true, sound: true) ?? false;
    } catch (_) {}
    return false;
  }

  static Future<void> schedule(int id, String title, String body, DateTime when) async {
    await init();
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'ver_reminder',
        'Reminders',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
      ),
      iOS: DarwinNotificationDetails(presentSound: true, presentAlert: true),
    );
    final at = tz.TZDateTime.from(when.toUtc(), tz.UTC);
    try {
      await _p.zonedSchedule(id, title, body, at, details, androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      try {
        await _p.zonedSchedule(id, title, body, at, details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (_) {}
    }
  }

  static Future<void> cancel(int id) async {
    try {
      await _p.cancel(id);
    } catch (_) {}
  }
}
