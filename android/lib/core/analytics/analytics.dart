import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Event catalog — mirrors `domain/analytics/events.py` server-side and the
/// iOS `AnalyticsEvent` enum. Keep names in lockstep across surfaces.
enum AnalyticsEvent {
  appOpened('app_opened'),
  screenViewed('screen_viewed'),
  coachLoggedIn('coach_logged_in'),
  clientListViewed('client_list_viewed'),
  checkinOpened('checkin_opened'),
  checkinReviewStarted('checkin_review_started'),
  checkinReviewCompleted('checkin_review_completed'),
  messageSent('message_sent'),
  planUpdated('plan_updated'),
  taskCreated('task_created'),
  taskCompleted('task_completed');

  const AnalyticsEvent(this.wireName);
  final String wireName;
}

/// PostHog wrapper — a total no-op until a `POSTHOG_API_KEY` is supplied via
/// env config (exact parity with iOS today, where the key is empty and the
/// SDK isn't linked). The call sites stay in place so wiring the SDK later is
/// a one-file change.
class Analytics {
  Analytics._();
  static final Analytics shared = Analytics._();

  bool get enabled => AppConfig.posthogApiKey.isNotEmpty;

  void configure() {
    if (!enabled) return;
    // Hook point: initialize the PostHog SDK here when the key ships.
  }

  void identify(int userId, {required String role, int? coachId}) {
    if (!enabled) return;
  }

  void capture(AnalyticsEvent event, [Map<String, Object?> props = const {}]) {
    if (!enabled) {
      if (kDebugMode) debugPrint('[analytics] ${event.wireName} $props');
      return;
    }
  }

  void screen(String name) => capture(AnalyticsEvent.screenViewed, {'screen': name});

  void reset() {
    if (!enabled) return;
  }
}
