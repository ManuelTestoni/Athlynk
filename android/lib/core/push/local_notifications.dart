import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications — used by the rest timer as the Android counterpart
/// of the iOS Live Activity: an ongoing notification with a live chronometer
/// countdown on the lock screen / shade.
class LocalNotifications {
  LocalNotifications._();
  static final LocalNotifications shared = LocalNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _restTimerId = 4201;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  /// Shows/updates the ongoing rest-timer notification counting down to
  /// [endAt].
  Future<void> showRestTimer({
    required String exerciseName,
    required DateTime endAt,
  }) async {
    await _ensureInit();
    await _plugin.show(
      _restTimerId,
      'RECUPERO',
      exerciseName,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'rest_timer',
          'Timer di recupero',
          channelDescription:
              'Countdown del recupero durante la sessione di allenamento',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          onlyAlertOnce: true,
          showWhen: true,
          usesChronometer: true,
          chronometerCountDown: true,
          when: endAt.millisecondsSinceEpoch,
          category: AndroidNotificationCategory.stopwatch,
        ),
      ),
    );
  }

  Future<void> cancelRestTimer() async {
    if (!_initialized) return;
    await _plugin.cancel(_restTimerId);
  }
}
