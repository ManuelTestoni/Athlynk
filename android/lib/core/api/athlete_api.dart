import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/models.dart';
import '../network/api_client.dart';

/// Athlete + role-agnostic endpoints — port of iOS `APIClient.swift`
/// (one method per endpoint, exact paths/keys preserved).
extension AthleteApi on ApiClient {
  /// `role` declares which app is logging in ("CLIENT" | "COACH"): the server
  /// only matches users with that role.
  Future<LoginResponse> login(String email, String password, String role) =>
      requestJson('/api/v1/auth/login', LoginResponse.fromJson,
          method: 'POST',
          body: {'email': email, 'password': password, 'role': role});

  Future<MeResponse> me() => requestJson('/api/v1/me', MeResponse.fromJson);

  Future<void> acceptTerms() =>
      requestVoid('/api/v1/accept-terms', body: const {});

  Future<List<WorkoutPlanDto>> workouts() async =>
      (await requestJson('/api/v1/workouts', WorkoutsResponse.fromJson)).plans;

  Future<List<NutritionPlanDto>> nutrition() async =>
      (await requestJson('/api/v1/nutrition', NutritionResponse.fromJson))
          .plans;

  Future<List<CheckDto>> checks() async =>
      (await requestJson('/api/v1/checks', ChecksResponse.fromJson)).pending;

  /// Full read-back of a past submitted check (storico).
  Future<CheckDetailDto> checkDetail(int responseId) =>
      requestJson('/api/v1/checks/$responseId', CheckDetailDto.fromJson);

  /// 20 per page.
  Future<NotificationsResponse> notifications({int offset = 0}) => requestJson(
      '/api/v1/notifications?offset=$offset', NotificationsResponse.fromJson);

  Future<void> markNotificationRead(int id) =>
      requestVoid('/api/v1/notifications/$id/read');

  Future<List<ConversationDto>> conversations() async => (await requestJson(
          '/api/v1/conversations', ConversationsResponse.fromJson))
      .conversations;

  /// One page of recent messages (oldest→newest). `before` = id of the oldest
  /// message held → server returns the page just before it.
  Future<MessagesResponse> messages(int conversation, {int? before}) {
    var path = '/api/v1/conversations/$conversation/messages';
    if (before != null) path += '?before=$before';
    return requestJson(path, MessagesResponse.fromJson);
  }

  /// Only messages newer than `since` (open-chat foreground poll).
  Future<List<MessageDto>> newMessages(int conversation, int since) async =>
      (await requestJson('/api/v1/conversations/$conversation/messages?since=$since',
              MessagesResponse.fromJson))
          .messages;

  Future<void> sendMessage(int conversation, String body) =>
      requestVoid('/api/v1/conversations/$conversation/send',
          body: {'body': body});

  /// Creates a PENDING appointment; returns its APPOINTMENT_REQUEST message.
  Future<MessageDto> requestAppointment(
    int conversation, {
    required String title,
    required String preferredDate,
    required String timeFrom,
    required String timeTo,
    String? notes,
  }) =>
      requestJson('/api/v1/conversations/$conversation/appointment',
          MessageDto.fromJson,
          method: 'POST',
          body: {
            'title': title,
            'preferred_date': preferredDate,
            'time_from': timeFrom,
            'time_to': timeTo,
            'notes': notes ?? '',
          });

  /// `action` = "accept" | "reject"; reject may carry a counter-proposal.
  Future<MessageDto> respondAppointment(
    int conversation,
    int appointmentId,
    String action, {
    String? counterDate,
    String? counterTime,
  }) =>
      requestJson(
          '/api/v1/conversations/$conversation/appointment/$appointmentId/respond',
          MessageDto.fromJson,
          method: 'POST',
          body: {
            'action': action,
            'counter_date': ?counterDate,
            'counter_time': ?counterTime,
          });

  /// Can be more than one when the athlete has multiple coaches.
  Future<List<SubscriptionDto>> subscription() async => (await requestJson(
          '/api/v1/subscription', SubscriptionListResponse.fromJson))
      .subscriptions;

  /// Stripe Billing Portal URL (only meaningful when `manageable`).
  Future<String> subscriptionBillingPortal(int id) async => (await requestJson(
          '/api/v1/subscription/$id/billing-portal', UrlResponse.fromJson,
          method: 'POST'))
      .url;

  Future<CalendarFeedDto> calendarFeed() =>
      requestJson('/api/v1/calendar-feed', CalendarFeedDto.fromJson);

  Future<CalendarFeedDto> rotateCalendarFeed() =>
      requestJson('/api/v1/calendar-feed', CalendarFeedDto.fromJson,
          method: 'POST', body: {'action': 'rotate'});

  Future<DashboardSummaryDto> dashboardSummary() =>
      requestJson('/api/v1/dashboard/summary', DashboardSummaryDto.fromJson);

  Future<AppointmentsResponse> appointments({int offset = 0}) => requestJson(
      '/api/v1/appointments?offset=$offset', AppointmentsResponse.fromJson);

  Future<ProgressResponse> progress({int offset = 0}) => requestJson(
      '/api/v1/progress?offset=$offset', ProgressResponse.fromJson);

  /// Sites the client has EVER recorded a value for (chart axis discovery).
  Future<MeasurementSitesDto> measurementSites() => requestJson(
      '/api/v1/progress/measurement-sites', MeasurementSitesDto.fromJson);

  Future<ExerciseTrendDto> exerciseTrend(int workoutExerciseId) => requestJson(
      '/api/v1/exercises/$workoutExerciseId/trend', ExerciseTrendDto.fromJson);

  Future<MeasurementCatalog> measurementCatalog() =>
      requestJson('/api/v1/measurement-catalog', MeasurementCatalog.fromJson);

  /// `type` = weight | circumference | skinfold; `key` = ISAK site (null for
  /// weight); `date` ISO yyyy-MM-dd.
  Future<void> addMeasurement({
    required String type,
    String? key,
    required double value,
    required String date,
  }) =>
      requestVoid('/api/v1/progress/measurement', body: {
        'type': type,
        'key': key,
        'value': value,
        'date': date,
      });

  Future<ClientProfileDto> profile() async =>
      (await requestJson('/api/v1/profile', ProfileResponse.fromJson)).profile;

  Future<ClientProfileDto> updateProfile(Map<String, dynamic> fields) async =>
      (await requestJson('/api/v1/profile', ProfileResponse.fromJson,
              method: 'PATCH', body: fields))
          .profile;

  /// Uploads the avatar (already-compressed JPEG bytes); returns the new URL.
  Future<String> uploadProfilePhoto(Uint8List jpeg) async {
    final bytes = await upload('/api/v1/profile/photo', files: [
      MapEntry('photo', MultipartFile.fromBytes(jpeg, filename: 'profile.jpg')),
    ]);
    return decodeObject(bytes, ProfilePhotoResponse.fromJson).profileImageUrl;
  }

  Future<String> uploadCoachPhoto(Uint8List jpeg) async {
    final bytes = await upload('/api/v1/coach/profile/photo', files: [
      MapEntry('photo', MultipartFile.fromBytes(jpeg, filename: 'profile.jpg')),
    ]);
    return decodeObject(bytes, ProfilePhotoResponse.fromJson).profileImageUrl;
  }

  /// Registers this device's push token. Best-effort, never throws.
  Future<void> registerDevice(String token, String bundleId) async {
    try {
      await requestVoid('/api/v1/devices/register', body: {
        'token': token,
        'platform': 'android',
        'bundle_id': bundleId,
      });
    } catch (_) {/* best-effort */}
  }

  /// 20 per page.
  Future<WorkoutHistoryResponse> workoutHistory({int offset = 0}) =>
      requestJson('/api/v1/workout-history?offset=$offset',
          WorkoutHistoryResponse.fromJson);

  Future<SessionDetailDto> workoutSessionDetail(int id) =>
      requestJson('/api/v1/workout-history/$id', SessionDetailDto.fromJson);

  Future<SupplementsResponse> supplements({int offset = 0}) => requestJson(
      '/api/v1/supplements?offset=$offset', SupplementsResponse.fromJson);

  Future<CoachDetailDto> coachDetail(int id) async =>
      (await requestJson('/api/v1/coaches/$id', CoachDetailResponse.fromJson))
          .coach;

  Future<SettingsDto> settings() async =>
      (await requestJson('/api/v1/settings', SettingsResponse.fromJson))
          .settings;

  Future<SettingsDto> updateSetting(String key, bool enabled) async =>
      (await requestJson('/api/v1/settings', SettingsResponse.fromJson,
              method: 'PATCH', body: {key: enabled}))
          .settings;

  Future<SettingsDto> updateFoodSearchMode(String mode) async =>
      (await requestJson('/api/v1/settings', SettingsResponse.fromJson,
              method: 'PATCH', body: {'food_search_mode': mode}))
          .settings;

  // ── Customizable dashboard layout (synced with the web grid) ──

  Future<DashboardLayoutResponse> dashboardLayout() => requestJson(
      '/api/v1/dashboard/layout', DashboardLayoutResponse.fromJson);

  /// Full-replace save. Widgets sent in array order with `y = index` so the
  /// web grid re-flows to the mobile ordering.
  Future<DashboardLayoutResponse> updateDashboardLayout(
      DashboardLayoutDto layout) {
    final widgets = layout.widgets
        .map((w) => {
              'id': w.id,
              'type': w.type,
              'x': w.x,
              'y': w.y,
              'size': w.size,
              'config': (w.config?.clientIds?.isNotEmpty ?? false)
                  ? {'client_ids': w.config!.clientIds}
                  : <String, dynamic>{},
            })
        .toList();
    return requestJson(
        '/api/v1/dashboard/layout', DashboardLayoutResponse.fromJson,
        method: 'PUT', body: {'version': layout.version, 'widgets': widgets});
  }

  Future<DashboardLayoutResponse> resetDashboardLayout() => requestJson(
      '/api/v1/dashboard/layout', DashboardLayoutResponse.fromJson,
      method: 'DELETE');

  /// Coach only: rows for the pinned-athletes widget, in the given order.
  Future<List<PinnedAthleteDto>> pinnedAthletes(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final qs = ids.join(',');
    return (await requestJson('/api/v1/coach/pinned-athletes?ids=$qs',
            PinnedAthletesResponse.fromJson))
        .athletes;
  }

  Future<List<SubscriptionPlanDto>> plans() async =>
      (await requestJson('/api/v1/plans', PlansResponse.fromJson)).plans;

  /// Hosted Stripe Checkout URL for an online-purchasable plan.
  Future<String> checkoutStart(int planId) async => (await requestJson(
          '/api/v1/checkout/start', CheckoutStartResponse.fromJson,
          method: 'POST', body: {'plan_id': planId}))
      .checkoutUrl;

  // ── Write flows: active session ──

  Future<SessionStartDto> sessionStart(int assignmentId, int dayId) =>
      requestJson('/api/v1/sessions/start', SessionStartDto.fromJson,
          method: 'POST',
          body: {'assignment_id': assignmentId, 'day_id': dayId});

  /// Log one set. `workoutExerciseId` for plan slots; `addedExerciseId`
  /// (catalog id) for in-session additions.
  Future<void> logSet({
    required int sessionId,
    int? workoutExerciseId,
    int? addedExerciseId,
    required int setNumber,
    int? reps,
    double? load,
    required String loadUnit,
    int? rpe,
    required bool completed,
    bool isExtraSet = false,
    bool substituted = false,
    int? actualExerciseId,
  }) =>
      requestVoid('/api/v1/sessions/$sessionId/log-set', body: {
        'set_number': setNumber,
        'load_unit': loadUnit,
        'completed': completed,
        'is_extra_set': isExtraSet,
        'exercise_substituted': substituted,
        'workout_exercise_id': workoutExerciseId,
        'exercise_id': addedExerciseId,
        'actual_exercise_id': actualExerciseId,
        'reps_done': reps,
        'load_used': load,
        'rpe': rpe,
      });

  /// Session-only plan deviations (add / remove / substitute).
  Future<void> setSessionOverrides({
    required int sessionId,
    required List<int> removed,
    required Map<int, int> substituted,
    required List<int> added,
  }) =>
      requestVoid('/api/v1/sessions/$sessionId/overrides', body: {
        'removed': removed,
        'substituted':
            substituted.map((k, v) => MapEntry(k.toString(), v)),
        'added': [
          for (final (i, id) in added.indexed) {'exercise_id': id, 'order': i}
        ],
      });

  /// `exerciseNotes` maps a workout_exercise_id to the athlete's volatile
  /// per-session note (stored server-side as a sentinel set_number=0 log).
  Future<void> finishSession(int sessionId,
          {String notes = '',
          bool interrupted = false,
          Map<int, String> exerciseNotes = const {}}) =>
      requestVoid('/api/v1/sessions/$sessionId/finish', body: {
        'notes': notes,
        'interrupted': interrupted,
        'exercise_notes': [
          for (final e in exerciseNotes.entries)
            if (e.value.trim().isNotEmpty)
              {'workout_exercise_id': e.key, 'notes': e.value},
        ],
      });

  /// Catalog search: by name, muscle group, or similar to a catalog id.
  Future<ExerciseSearchResponse> searchExercises({
    String q = '',
    String muscleGroup = '',
    int? similarTo,
    bool includeGroups = false,
  }) =>
      requestJson('/api/v1/exercises/search', ExerciseSearchResponse.fromJson,
          query: {
            'limit': '30',
            if (q.isNotEmpty) 'q': q,
            if (muscleGroup.isNotEmpty) 'muscle_group': muscleGroup,
            if (similarTo != null) 'similar_to': '$similarTo',
            if (includeGroups) 'include_groups': '1',
          });

  /// Dual-auth catalog endpoint (NOT under /api/v1) — shared by both apps.
  Future<ExerciseCatalogDetailDto> exerciseCatalogDetail(int id) =>
      requestJson('/api/exercises/$id/', ExerciseCatalogDetailDto.fromJson);

  Future<List<ExerciseHistoryItemDto>> progressExercises() async =>
      (await requestJson(
              '/api/v1/progress/exercises', ExercisesHistoryResponse.fromJson))
          .exercises;

  /// History-based trend keyed by NAME (covers substituted/added movements).
  Future<ExerciseTrendDto> exerciseTrendByName(String name) => requestJson(
      '/api/v1/exercises/trend-by-name', ExerciseTrendDto.fromJson,
      query: {'name': name});

  /// Submit a multi-step check. `answers` keyed by question id (String or
  /// `List<String>`); `attachments` maps an `allegato` question id to
  /// already-compressed JPEG bytes → multipart when present.
  Future<void> submitCheck(
    int instanceId,
    Map<String, dynamic> answers, {
    Map<String, List<Uint8List>> attachments = const {},
  }) async {
    final path = '/api/v1/checks/$instanceId/submit';
    final hasFiles = attachments.values.any((l) => l.isNotEmpty);
    if (!hasFiles) {
      await requestVoid(path, body: {'answers': answers});
      return;
    }
    final files = <MapEntry<String, MultipartFile>>[];
    attachments.forEach((qid, images) {
      for (final (i, data) in images.indexed) {
        files.add(MapEntry('attachment_$qid',
            MultipartFile.fromBytes(data, filename: '${qid}_$i.jpg')));
      }
    });
    await upload(path, fields: {'answers': jsonEncode(answers)}, files: files);
  }

  Future<PrimaValutazioneDto> primaValutazione() =>
      requestJson('/api/v1/prima-valutazione', PrimaValutazioneDto.fromJson);

  Future<void> forgotPassword(String email) =>
      requestVoid('/api/v1/auth/forgot-password', body: {'email': email});

  Future<void> deleteAccount() =>
      requestVoid('/api/v1/account', method: 'DELETE');

  Future<void> completeTutorial() => requestVoid('/api/v1/tutorial/complete');

  // ── MACRO-mode logging ──

  Future<FoodSearchResponse> searchFoods(
    String query, {
    String? filter,
    String? cat,
    bool includeCats = false,
  }) =>
      requestJson('/api/v1/nutrition/foods', FoodSearchResponse.fromJson,
          query: {
            if (query.isNotEmpty) 'q': query,
            'filter': ?filter,
            'cat': ?cat,
            if (includeCats) 'include_cats': '1',
          });

  /// `date` ISO yyyy-MM-dd loads a past day; null = today.
  Future<MacroDayDto> macroDay(int assignment, {String? date}) async {
    var path = '/api/v1/nutrition/assignments/$assignment/macro-day';
    if (date != null) path += '?date=$date';
    return (await requestJson(path, MacroDayResponse.fromJson)).macroDay;
  }

  /// 14 per page.
  Future<MacroHistoryResponse> macroHistory(int assignment,
          {int offset = 0}) =>
      requestJson(
          '/api/v1/nutrition/assignments/$assignment/macro-history?offset=$offset',
          MacroHistoryResponse.fromJson);

  Future<void> addMacroLog({
    required int assignment,
    required int foodId,
    required double quantityG,
    String? mealName,
    String? date,
  }) =>
      requestVoid('/api/v1/nutrition/assignments/$assignment/macro-log',
          body: {
            'food_id': foodId,
            'quantity_g': quantityG,
            if (mealName != null && mealName.isNotEmpty) 'meal_name': mealName,
            'date': ?date,
          });

  Future<void> deleteMacroLog(int entryId) =>
      requestVoid('/api/v1/nutrition/macro-log/$entryId', method: 'DELETE');

  Future<JourneyResponse> journey({int offset = 0}) => requestJson(
      '/api/v1/journey?offset=$offset', JourneyResponse.fromJson);
}
