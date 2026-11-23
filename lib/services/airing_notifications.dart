import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'airing_service.dart';

/// Local notifications for airing episodes (0.2.10) — on-device
/// scheduling only, NO push server. iOS fires them through
/// UNUserNotificationCenter even when the app is closed (that is
/// the OS's job once scheduled). Delivery itself is phone-verified
/// only; the VM cannot prove it.
///
/// Flow: [init] once at launch (never prompts) → [requestPermission]
/// once at first use from the Home airing section (never on every
/// launch) → [scheduleAiring] after each airing fetch, 15 minutes
/// before each followed title airs.
class AiringNotifications {
  AiringNotifications({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// Minutes before airing the alert fires.
  static const int kNotifyMinutesBefore = 15;

  /// Fire time for one entry — 15 minutes before it airs (pure,
  /// unit-tested).
  static DateTime fireTimeFor(AiringEntry entry) =>
      entry.airingAt.subtract(const Duration(minutes: kNotifyMinutesBefore));

  /// Entries worth scheduling right now: fire time still in the
  /// future (pure — unit-tested). Past airings are never scheduled.
  static List<AiringEntry> schedulable(
    List<AiringEntry> entries, {
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    return entries.where((AiringEntry e) => fireTimeFor(e).isAfter(at)).toList();
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      // Never prompt here — the permission dialog appears once at
      // first use from the Home airing section.
      const DarwinInitializationSettings ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(iOS: ios),
      );
      _initialized = true;
    } catch (_) {
      // Notifications are best-effort: a failed init must never
      // break launch or the airing row.
      _initialized = false;
    }
  }

  /// Ask the iOS permission dialog (alert + badge + sound).
  /// Returns true when granted. Never throws.
  Future<bool> requestPermission() async {
    try {
      final IOSFlutterLocalNotificationsPlugin? ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final bool? granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// True when iOS currently allows alerts. Never throws.
  Future<bool> get isPermissionGranted async {
    try {
      final IOSFlutterLocalNotificationsPlugin? ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final NotificationsEnabledOptions? options =
          await ios?.checkPermissions();
      return options?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Replace the whole schedule with [entries] (only followed
  /// titles — the caller gates on AniList-connected + toggle on).
  /// Each fires 15 minutes before its episode airs. Never throws.
  Future<void> scheduleAiring(List<AiringEntry> entries) async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
      for (final AiringEntry entry in schedulable(entries)) {
        await _plugin.zonedSchedule(
          id: entry.anilistId,
          title: 'EP ${entry.episode} airs soon',
          body: '${entry.title} — Episode ${entry.episode} airs '
              'in 15 minutes',
          scheduledDate: tz.TZDateTime.from(fireTimeFor(entry), tz.UTC),
          notificationDetails: const NotificationDetails(
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'airing:${entry.anilistId}',
        );
      }
    } catch (_) {
      // Best-effort: scheduling never breaks the app.
    }
  }

  /// Drop every scheduled airing alert (toggle off). Never throws.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Best-effort.
    }
  }
}
