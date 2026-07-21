import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/models.dart';
import '../network/api_client.dart';

/// Coach-surface endpoints (`/api/v1/coach/...` + the dual-auth `/api/...`
/// builder tier) — port of `AthlynkCoach/Core/CoachAPI.swift`.
extension CoachApi on ApiClient {
  // ── Dashboard ──

  Future<CoachDashboardDto> coachDashboard() =>
      requestJson('/api/v1/coach/dashboard', CoachDashboardDto.fromJson);

  // ── Agenda ──

  Future<CoachAgendaResponse> coachAgenda({int offset = 0}) => requestJson(
      '/api/v1/coach/agenda?offset=$offset', CoachAgendaResponse.fromJson);

  Future<void> coachCreateAppointment(Map<String, dynamic> body) =>
      requestVoid('/api/v1/coach/agenda/create', body: body);

  Future<void> coachDeleteAppointment(int id) =>
      requestVoid('/api/v1/coach/agenda/$id', method: 'DELETE');

  // ── Clients ──

  Future<CoachClientsResponse> coachClients({
    String q = '',
    String status = '',
    bool hasChecks = false,
    int offset = 0,
    int limit = 30,
  }) =>
      requestJson('/api/v1/coach/clients', CoachClientsResponse.fromJson,
          query: {
            if (q.isNotEmpty) 'q': q,
            if (status.isNotEmpty) 'status': status,
            if (hasChecks) 'has_checks': '1',
            'offset': '$offset',
            'limit': '$limit',
          });

  Future<void> coachCreateClient(Map<String, dynamic> body) =>
      requestVoid('/api/v1/coach/clients/create', body: body);

  Future<CoachClientDetailDto> coachClientDetail(int id) => requestJson(
      '/api/v1/coach/clients/$id', CoachClientDetailDto.fromJson);

  Future<ProgressResponse> coachClientProgress(int id, {int offset = 0}) =>
      requestJson('/api/v1/coach/clients/$id/progress?offset=$offset',
          ProgressResponse.fromJson);

  Future<CoachChecksResponse> coachClientChecks(int id, {int offset = 0}) =>
      requestJson('/api/v1/coach/clients/$id/checks?offset=$offset',
          CoachChecksResponse.fromJson);

  Future<SessionBriefListDto> coachClientSessions(int id,
          {int offset = 0}) =>
      requestJson('/api/v1/coach/clients/$id/sessions?offset=$offset',
          SessionBriefListDto.fromJson);

  Future<SessionDetailDto> coachSessionDetail(int sessionId) => requestJson(
      '/api/v1/coach/sessions/$sessionId', SessionDetailDto.fromJson);

  Future<MacroHistoryResponse> coachClientMacroHistory(int id,
          {int offset = 0}) =>
      requestJson('/api/v1/coach/clients/$id/macro-history?offset=$offset',
          MacroHistoryResponse.fromJson);

  Future<void> coachAddClientMeasurement(
    int clientId, {
    required String type,
    String? key,
    required double value,
    required String date,
  }) =>
      requestVoid('/api/v1/coach/clients/$clientId/measurement', body: {
        'type': type,
        'key': key,
        'value': value,
        'date': date,
      });

  // Percorso (journey + phases CRUD)

  Future<JourneyResponse> coachClientJourney(int id, {int offset = 0}) =>
      requestJson('/api/v1/coach/clients/$id/percorso?offset=$offset',
          JourneyResponse.fromJson);

  Future<void> coachCreatePhase(int clientId, Map<String, dynamic> body) =>
      requestVoid('/api/v1/coach/clients/$clientId/percorso/phases',
          body: body);

  Future<void> coachUpdatePhase(
          int clientId, int phaseId, Map<String, dynamic> body) =>
      requestVoid('/api/v1/coach/clients/$clientId/percorso/phases/$phaseId',
          method: 'PATCH', body: body);

  Future<void> coachDeletePhase(int clientId, int phaseId) =>
      requestVoid('/api/v1/coach/clients/$clientId/percorso/phases/$phaseId',
          method: 'DELETE');

  // Native progress charts (dual-auth web endpoints)

  Future<CoachProgressKpiDto> coachClientKpi(int id) => requestJson(
      '/api/coach/clienti/$id/progressi/kpi/', CoachProgressKpiDto.fromJson);

  Future<List<AdherencePointDto>> coachClientAdherence(int id) async {
    final raw = await requestAny('/api/coach/clienti/$id/progressi/aderenza/');
    final list = (raw is Map ? raw['points'] : raw) as List? ?? const [];
    return [
      for (final e in list)
        AdherencePointDto.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<List<RpePointDto>> coachClientRpe(int id) async {
    final raw = await requestAny('/api/coach/clienti/$id/progressi/rpe/');
    final list = (raw is Map ? raw['points'] : raw) as List? ?? const [];
    return [
      for (final e in list) RpePointDto.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<ExerciseTrendDto> coachClientExerciseTrend(
          int clientId, int workoutExerciseId) =>
      requestJson(
          '/api/v1/coach/clients/$clientId/exercises/$workoutExerciseId/trend',
          ExerciseTrendDto.fromJson);

  /// Raw loads series ({series:[{date, load_max}], progress_4w}) for the
  /// athlete_training dashboard widget. Dual-auth web endpoint (same data as
  /// the web widget).
  Future<Map<String, dynamic>> coachClientLoads(int id) async {
    final raw = await requestAny('/api/coach/clienti/$id/progressi/carichi/');
    return (raw as Map).cast<String, dynamic>();
  }

  /// Raw weekly volume ({weeks, muscles, series:{muscle:[...]}}) per muscle
  /// group for the athlete_training widget.
  Future<Map<String, dynamic>> coachClientVolume(int id) async {
    final raw = await requestAny('/api/coach/clienti/$id/progressi/volume/');
    return (raw as Map).cast<String, dynamic>();
  }

  // ── Checks ──

  Future<CoachChecksResponse> coachChecks(
          {String filter = 'pending', int offset = 0}) =>
      requestJson('/api/v1/coach/checks?filter=$filter&offset=$offset',
          CoachChecksResponse.fromJson);

  Future<CoachCheckDetailDto> coachCheckDetail(int id) async =>
      (await requestJson(
              '/api/v1/coach/checks/$id', CoachCheckDetailResponse.fromJson))
          .check;

  Future<void> coachCheckFeedback(int id, String feedback) => requestVoid(
      '/api/v1/coach/checks/$id/feedback',
      body: {'feedback': feedback});

  Future<CheckCatalog> coachCheckCatalog() =>
      requestJson('/api/v1/coach/check-catalog', CheckCatalog.fromJson);

  Future<CoachCheckTemplatesResponse> coachCheckTemplates() => requestJson(
      '/api/v1/coach/check-templates', CoachCheckTemplatesResponse.fromJson);

  Future<CoachCheckTemplateDetail> coachCheckTemplateDetail(int id) =>
      requestJson('/api/v1/coach/check-templates/$id',
          CoachCheckTemplateDetail.fromJson);

  Future<void> coachCreateCheckTemplate(Map<String, dynamic> body) =>
      requestVoid('/api/v1/coach/check-templates/create', body: body);

  Future<void> coachUpdateCheckTemplate(int id, Map<String, dynamic> body) =>
      requestVoid('/api/v1/coach/check-templates/$id/update', body: body);

  Future<void> coachDuplicateCheckTemplate(int id) =>
      requestVoid('/api/v1/coach/check-templates/$id/duplicate');

  Future<void> coachDeleteCheckTemplate(int id) =>
      requestVoid('/api/v1/coach/check-templates/$id/delete');

  Future<void> coachRestoreCheckTemplate(int id) =>
      requestVoid('/api/v1/coach/check-templates/$id/restore');

  /// recurrence_type: once | weekly | monthly | end_program.
  Future<void> coachAssignCheckTemplate(int id, Map<String, dynamic> body) =>
      requestVoid('/api/v1/coach/check-templates/$id/assign', body: body);

  // ── Plans (library) ──

  Future<CoachWorkoutsResponse> coachWorkouts(
          {String q = '', int? folderId, int offset = 0}) =>
      requestJson('/api/v1/coach/workouts', CoachWorkoutsResponse.fromJson,
          query: {
            if (q.isNotEmpty) 'q': q,
            if (folderId != null) 'folder_id': '$folderId',
            'offset': '$offset',
          });

  Future<CoachWorkoutsResponse> coachNutrition(
          {String q = '', int? folderId, int offset = 0}) =>
      requestJson('/api/v1/coach/nutrition', CoachWorkoutsResponse.fromJson,
          query: {
            if (q.isNotEmpty) 'q': q,
            if (folderId != null) 'folder_id': '$folderId',
            'offset': '$offset',
          });

  /// Read-only plan detail — shares the athlete wire shape.
  Future<WorkoutPlanDto> coachWorkoutDetail(int id) async {
    final raw = await requestAny('/api/v1/coach/workouts/$id');
    final map = raw as Map<String, dynamic>;
    final plan = (map['plan'] ?? map) as Map<String, dynamic>;
    return WorkoutPlanDto.fromJson({
      'assignment_id': plan['assignment_id'] ?? 0,
      'plan_id': plan['plan_id'] ?? plan['id'] ?? id,
      ...plan,
    });
  }

  Future<Map<String, dynamic>> coachNutritionDetail(int id) async {
    final raw = await requestAny('/api/v1/coach/nutrition/$id');
    return (raw as Map<String, dynamic>);
  }

  // ── Builder tier (dual-auth /api/..., same endpoints as the web app) ──

  Future<Map<String, dynamic>> workoutBuilderPayload(int id) async =>
      (await requestAny('/api/v1/coach/workouts/$id/builder'))
          as Map<String, dynamic>;

  /// Creates/saves a workout plan draft; returns `{id: ...}`.
  Future<Map<String, dynamic>> saveWorkoutPlan(Map<String, dynamic> body,
      {int? planId}) async {
    final path = planId == null
        ? '/api/allenamenti/save/'
        : '/api/allenamenti/$planId/save/';
    return (await requestAny(path, method: 'POST', body: body))
        as Map<String, dynamic>;
  }

  /// mode: template | assign | draft (body carries client_ids on assign).
  Future<void> finalizeWorkoutPlan(int planId, Map<String, dynamic> body) =>
      requestVoid('/api/allenamenti/$planId/finalize/', body: body);

  Future<void> deleteWorkoutPlan(int planId) =>
      requestVoid('/api/allenamenti/$planId/elimina/');

  Future<void> duplicateWorkoutPlan(int planId) =>
      requestVoid('/api/allenamenti/$planId/duplica/');

  Future<Map<String, dynamic>> progressionGrid(int planId, int dayId) async =>
      (await requestAny('/api/allenamenti/$planId/progression/day/$dayId/grid/'))
          as Map<String, dynamic>;

  Future<void> saveProgressionCell(int planId, Map<String, dynamic> body) =>
      requestVoid('/api/allenamenti/$planId/progression/cell/', body: body);

  Future<Map<String, dynamic>> createNutritionPlan(
          Map<String, dynamic> body) async =>
      (await requestAny('/api/nutrizione/piani/crea/',
          method: 'POST', body: body)) as Map<String, dynamic>;

  Future<void> updateNutritionPlan(int id, Map<String, dynamic> body) =>
      requestVoid('/api/nutrizione/piani/$id/modifica/', body: body);

  Future<void> deleteNutritionPlan(int id) =>
      requestVoid('/api/nutrizione/piani/$id/elimina/');

  Future<void> duplicateNutritionPlan(int id) =>
      requestVoid('/api/nutrizione/piani/$id/duplica/');

  Future<void> assignNutritionPlan(int id, Map<String, dynamic> body) =>
      requestVoid('/api/nutrizione/piani/$id/assegna/', body: body);

  /// Food DB search used by the coach builders.
  Future<FoodSearchResponse> coachSearchFoods(String q,
          {bool includeCats = false}) =>
      requestJson('/api/nutrizione/alimenti/', FoodSearchResponse.fromJson,
          query: {
            if (q.isNotEmpty) 'q': q,
            if (includeCats) 'include_cats': '1',
          });

  // AI/Excel import wizard

  Future<Map<String, dynamic>> importPlanFile({
    required bool workout,
    required bool excel,
    required Uint8List bytes,
    required String filename,
  }) async {
    final domain = workout ? 'allenamenti' : 'nutrizione';
    final kind = excel ? 'excel' : 'pdf';
    final res = await upload('/api/$domain/import/$kind/', files: [
      MapEntry('file', MultipartFile.fromBytes(bytes, filename: filename)),
    ]);
    return jsonDecode(String.fromCharCodes(res)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> importPlanStatus(
          {required bool workout, required String jobId}) async =>
      (await requestAny(
              '/api/${workout ? 'allenamenti' : 'nutrizione'}/import/pdf/status/?job_id=$jobId'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> importPlanConfirm(
          {required bool workout, required Map<String, dynamic> body}) async =>
      (await requestAny(
              '/api/${workout ? 'allenamenti' : 'nutrizione'}/import/conferma/',
              method: 'POST',
              body: body)) as Map<String, dynamic>;

  // Folders (workout/nutrition/check)

  Future<List<CoachFolder>> coachFolders(String domain) async {
    final raw = await requestAny('/api/$domain/cartelle/');
    final list = (raw is Map ? raw['folders'] : raw) as List? ?? const [];
    return [
      for (final e in list) CoachFolder.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<void> coachCreateFolder(String domain, String title) =>
      requestVoid('/api/$domain/cartelle/', body: {'title': title});

  Future<void> coachRenameFolder(String domain, int id, String title) =>
      requestVoid('/api/$domain/cartelle/$id/',
          method: 'PATCH', body: {'title': title});

  Future<void> coachDeleteFolder(String domain, int id) =>
      requestVoid('/api/$domain/cartelle/$id/', method: 'DELETE');

  // ── Subscriptions & Connect ──

  Future<CoachSubscriptionsDto> coachSubscriptions({int offset = 0}) =>
      requestJson('/api/v1/coach/subscriptions?offset=$offset',
          CoachSubscriptionsDto.fromJson);

  Future<List<CoachSubscriptionPlanRow>> coachSubscriptionPlans() async {
    final raw = await requestAny('/api/v1/coach/subscription-plans');
    final list = (raw is Map ? raw['plans'] : raw) as List? ?? const [];
    return [
      for (final e in list)
        CoachSubscriptionPlanRow.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<void> coachCreateSubscriptionPlan(Map<String, dynamic> body) =>
      requestVoid('/api/v1/coach/subscription-plans/create', body: body);

  Future<void> coachUpdateSubscriptionPlan(
          int id, Map<String, dynamic> body) =>
      requestVoid('/api/v1/coach/subscription-plans/$id',
          method: 'PUT', body: body);

  Future<void> coachDeleteSubscriptionPlan(int id) =>
      requestVoid('/api/v1/coach/subscription-plans/$id', method: 'DELETE');

  Future<CoachConnectStartResponse> coachConnectStart() => requestJson(
      '/api/v1/coach/connect/start', CoachConnectStartResponse.fromJson,
      method: 'POST');

  Future<CoachConnectStatusResponse> coachConnectStatus() => requestJson(
      '/api/v1/coach/connect/status', CoachConnectStatusResponse.fromJson);

  Future<String> coachBillingPortal() async => (await requestJson(
          '/api/v1/coach/billing-portal', UrlResponse.fromJson,
          method: 'POST'))
      .url;

  // ── Analytics ──

  Future<CoachAnalyticsDto> coachAnalytics() =>
      requestJson('/api/v1/coach/analytics', CoachAnalyticsDto.fromJson);

  Future<CoachBusinessKpis> coachAnalyticsBusiness() async {
    final raw = await requestAny('/api/v1/coach/analytics/business');
    final map = raw as Map<String, dynamic>;
    final kpis = (map['kpis'] ?? map) as Map<String, dynamic>;
    return CoachBusinessKpis.fromJson(kpis);
  }

  Future<CoachRiskResponse> coachAnalyticsRisk(
          {String riskClass = 'all', int offset = 0}) =>
      requestJson('/api/v1/coach/analytics/risk?class=$riskClass&offset=$offset',
          CoachRiskResponse.fromJson);

  // ── Messaging ──

  Future<List<CoachConversation>> coachConversations() async =>
      (await requestJson('/api/v1/coach/conversations',
              CoachConversationsResponse.fromJson))
          .conversations;

  Future<MessagesResponse> coachMessages(int conversation, {int? before}) {
    var path = '/api/v1/coach/conversations/$conversation/messages';
    if (before != null) path += '?before=$before';
    return requestJson(path, MessagesResponse.fromJson);
  }

  Future<List<MessageDto>> coachNewMessages(int conversation, int since) async =>
      (await requestJson(
              '/api/v1/coach/conversations/$conversation/messages?since=$since',
              MessagesResponse.fromJson))
          .messages;

  Future<void> coachSendMessage(int conversation, String body) =>
      requestVoid('/api/v1/coach/conversations/$conversation/send',
          body: {'body': body});

  Future<MessageDto> coachRespondAppointment(
    int conversation,
    int appointmentId,
    String action, {
    String? counterDate,
    String? counterTime,
  }) =>
      requestJson(
          '/api/v1/coach/conversations/$conversation/appointment/$appointmentId/respond',
          MessageDto.fromJson,
          method: 'POST',
          body: {
            'action': action,
            'counter_date': ?counterDate,
            'counter_time': ?counterTime,
          });

  Future<List<CoachMessageableClient>> coachMessageableClients() async {
    final raw = await requestAny('/api/v1/coach/messageable-clients');
    final list = (raw is Map ? raw['clients'] : raw) as List? ?? const [];
    return [
      for (final e in list)
        CoachMessageableClient.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<CoachStartConversationResponse> coachStartConversation(
          int clientId, String body) =>
      requestJson('/api/v1/coach/conversations/start',
          CoachStartConversationResponse.fromJson,
          method: 'POST', body: {'client_id': clientId, 'body': body});

  Future<CoachAutoMessagesResponse> coachAutoMessages() => requestJson(
      '/api/v1/coach/auto-messages', CoachAutoMessagesResponse.fromJson);

  Future<void> coachUpdateAutoMessage(
          String key, {required bool enabled, required String body}) =>
      requestVoid('/api/v1/coach/auto-messages', method: 'PATCH', body: {
        'key': key,
        'enabled': enabled,
        'body': body,
      });

  // ── Profile / resources / supplements ──

  Future<CoachProfileDto> coachProfile() async => (await requestJson(
          '/api/v1/coach/profile', CoachProfileResponse.fromJson))
      .profile;

  Future<CoachProfileDto> coachUpdateProfile(Map<String, dynamic> fields) async =>
      (await requestJson('/api/v1/coach/profile', CoachProfileResponse.fromJson,
              method: 'PATCH', body: fields))
          .profile;

  Future<CalendarFeedDto> coachCalendarFeed() =>
      requestJson('/api/v1/coach/calendar-feed', CalendarFeedDto.fromJson);

  Future<CalendarFeedDto> coachRotateCalendarFeed() =>
      requestJson('/api/v1/coach/calendar-feed', CalendarFeedDto.fromJson,
          method: 'POST', body: {'action': 'rotate'});

  Future<CoachResourcesResponse> coachResources() =>
      requestJson('/api/v1/coach/resources', CoachResourcesResponse.fromJson);

  Future<CoachSupplementsResponse> coachSupplements() => requestJson(
      '/api/v1/coach/supplements', CoachSupplementsResponse.fromJson);

  Future<CoachSupplementDetail> coachSupplementDetail(int id) => requestJson(
      '/api/v1/coach/supplements/$id', CoachSupplementDetail.fromJson);

  Future<void> coachSaveSupplement(Map<String, dynamic> body) =>
      requestVoid('/api/v1/coach/supplements/save', body: body);

  Future<void> coachDeleteSupplement(int id) =>
      requestVoid('/api/v1/coach/supplements/$id/delete');

  Future<void> coachAssignSupplement(int id, List<int> clientIds) =>
      requestVoid('/api/v1/coach/supplements/$id/assign',
          body: {'client_ids': clientIds});

  Future<List<CoachAssignableClient>> coachSupplementAssignableClients(
      {int? excludeProtocolId}) async {
    var path = '/api/v1/coach/supplements/assignable-clients';
    if (excludeProtocolId != null) {
      path += '?exclude_protocol_id=$excludeProtocolId';
    }
    final raw = await requestAny(path);
    final list = (raw is Map ? raw['clients'] : raw) as List? ?? const [];
    return [
      for (final e in list)
        CoachAssignableClient.fromJson(e as Map<String, dynamic>)
    ];
  }

  // ── Chiron ──

  Future<ChironHistoryResponse> chironHistory({int limit = 30, int? before}) {
    var path = '/api/v1/coach/chiron/history/?limit=$limit';
    if (before != null) path += '&before=$before';
    return requestJson(path, ChironHistoryResponse.fromJson);
  }

  /// SSE stream of `data:` frames for one chat turn.
  Stream<String> chironChatStream(String message, {CancelToken? cancelToken}) =>
      sse('/api/v1/coach/chiron/chat/stream/',
          body: {'message': message}, cancelToken: cancelToken);

  Future<void> chironClear() => requestVoid('/api/v1/coach/chiron/clear/');

  Future<Map<String, dynamic>> chironExecuteAction(
          Map<String, dynamic> body) async =>
      (await requestAny('/api/v1/coach/chiron/azione/esegui/',
          method: 'POST', body: body)) as Map<String, dynamic>;
}
