import 'package:freezed_annotation/freezed_annotation.dart';

part 'coach.freezed.dart';
part 'coach.g.dart';

/// Coach-app DTOs — port of `AthlynkCoach/Core/CoachModels.swift`
/// (the `/api/v1/coach` JSON shapes).

@freezed
abstract class CoachClient with _$CoachClient {
  const CoachClient._();
  const factory CoachClient({
    required int id,
    @Default('') String firstName,
    @Default('') String lastName,
    @Default('') String displayName,
    String? profileImageUrl,
    String? sport,
    // Extended fields (present only in client detail).
    String? phone,
    String? gender,
    String? birthDate,
    double? weightKg,
    String? email,
  }) = _CoachClient;

  factory CoachClient.fromJson(Map<String, dynamic> json) =>
      _$CoachClientFromJson(json);

  String get fullName => '$firstName $lastName'.trim();
}

@freezed
abstract class PlatformPurchaseDto with _$PlatformPurchaseDto {
  const factory PlatformPurchaseDto({
    @Default('') String plan,
    @Default('') String status,
    String? billingInterval,
    String? currentPeriodEnd,
  }) = _PlatformPurchaseDto;

  factory PlatformPurchaseDto.fromJson(Map<String, dynamic> json) =>
      _$PlatformPurchaseDtoFromJson(json);
}

@freezed
abstract class CoachProfileDto with _$CoachProfileDto {
  const CoachProfileDto._();
  const factory CoachProfileDto({
    required int id,
    @Default('') String firstName,
    @Default('') String lastName,
    String? professionalType,
    String? specialization,
    String? city,
    String? phone,
    String? bio,
    String? description,
    String? certifications,
    int? yearsExperience,
    String? profileImageUrl,
    String? socialInstagram,
    String? socialYoutube,
    String? socialTiktok,
    String? socialWebsite,
    String? email,
    String? stripeConnectAccountId,
    @Default(false) bool stripeConnectChargesEnabled,
    @Default(false) bool stripeConnectDetailsSubmitted,
    @Default('') String brandName,
    @Default('') String brandPrimary,
    @Default('') String brandAccent,
    PlatformPurchaseDto? platformPurchase,
  }) = _CoachProfileDto;

  factory CoachProfileDto.fromJson(Map<String, dynamic> json) =>
      _$CoachProfileDtoFromJson(json);

  String get fullName => '$firstName $lastName'.trim();

  String get roleLabel => switch ((professionalType ?? '').toUpperCase()) {
        'ALLENATORE' => 'Allenatore',
        'NUTRIZIONISTA' => 'Nutrizionista',
        _ => 'Coach',
      };
}

@freezed
abstract class CoachProfileResponse with _$CoachProfileResponse {
  const factory CoachProfileResponse({
    required CoachProfileDto profile,
  }) = _CoachProfileResponse;

  factory CoachProfileResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachProfileResponseFromJson(json);
}

// ── Stripe Connect ──

@freezed
abstract class CoachConnectStartResponse with _$CoachConnectStartResponse {
  const factory CoachConnectStartResponse({
    required String accountLinkUrl,
  }) = _CoachConnectStartResponse;

  factory CoachConnectStartResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachConnectStartResponseFromJson(json);
}

@freezed
abstract class CoachConnectStatusResponse with _$CoachConnectStatusResponse {
  const factory CoachConnectStatusResponse({
    String? stripeConnectAccountId,
    @Default(false) bool stripeConnectChargesEnabled,
    @Default(false) bool stripeConnectDetailsSubmitted,
  }) = _CoachConnectStatusResponse;

  factory CoachConnectStatusResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachConnectStatusResponseFromJson(json);
}

// ── Dashboard ──

@freezed
abstract class CoachStats with _$CoachStats {
  const factory CoachStats({
    @Default(0) int activeClients,
    @Default(0) int pendingChecks,
    @Default(0) int appointmentsToday,
    @Default(0) int unreadMessages,
  }) = _CoachStats;

  factory CoachStats.fromJson(Map<String, dynamic> json) =>
      _$CoachStatsFromJson(json);
}

@freezed
abstract class CoachAgendaItem with _$CoachAgendaItem {
  const factory CoachAgendaItem({
    required int id,
    required String title,
    String? type,
    String? description,
    String? start,
    int? durationMinutes,
    String? location,
    String? meetingUrl,
    String? status,
    CoachClient? client,
  }) = _CoachAgendaItem;

  factory CoachAgendaItem.fromJson(Map<String, dynamic> json) =>
      _$CoachAgendaItemFromJson(json);
}

@freezed
abstract class CoachActivity with _$CoachActivity {
  const factory CoachActivity({
    required int id,
    required String type,
    required String title,
    String? body,
    String? createdAt,
  }) = _CoachActivity;

  factory CoachActivity.fromJson(Map<String, dynamic> json) =>
      _$CoachActivityFromJson(json);
}

@freezed
abstract class CoachInsight with _$CoachInsight {
  const factory CoachInsight({
    @Default(0) int checksThisWeek,
    @Default('') String text,
  }) = _CoachInsight;

  factory CoachInsight.fromJson(Map<String, dynamic> json) =>
      _$CoachInsightFromJson(json);
}

@freezed
abstract class CoachDashboardDto with _$CoachDashboardDto {
  const factory CoachDashboardDto({
    required CoachProfileDto coach,
    required CoachStats stats,
    @Default([]) List<CoachAgendaItem> agenda,
    @Default([]) List<CoachActivity> activity,
    required CoachInsight insight,
  }) = _CoachDashboardDto;

  factory CoachDashboardDto.fromJson(Map<String, dynamic> json) =>
      _$CoachDashboardDtoFromJson(json);
}

@freezed
abstract class CoachAgendaResponse with _$CoachAgendaResponse {
  const factory CoachAgendaResponse({
    @Default([]) List<CoachAgendaItem> appointments,
    @Default(false) bool hasMore,
  }) = _CoachAgendaResponse;

  factory CoachAgendaResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachAgendaResponseFromJson(json);
}

// ── Clients ──

@freezed
abstract class CoachClientRow with _$CoachClientRow {
  const CoachClientRow._();
  const factory CoachClientRow({
    required int id,
    @Default('') String displayName,
    @Default('') String firstName,
    @Default('') String lastName,
    String? profileImageUrl,
    String? relationshipType,
    String? status,
    String? startDate,
    String? activeWorkout,
    String? activePlan,
    String? lastCheckAt,
  }) = _CoachClientRow;

  factory CoachClientRow.fromJson(Map<String, dynamic> json) =>
      _$CoachClientRowFromJson(json);

  String get relationshipLabel =>
      switch ((relationshipType ?? '').toUpperCase()) {
        'WORKOUT' => 'Allenamento',
        'NUTRITION' => 'Nutrizione',
        'FULL' => 'Full Coaching',
        _ => 'Cliente',
      };
}

@freezed
abstract class CoachClientsResponse with _$CoachClientsResponse {
  const factory CoachClientsResponse({
    @Default([]) List<CoachClientRow> clients,
    @Default(0) int total,
    @Default(0) int active,
    @Default(false) bool hasMore,
  }) = _CoachClientsResponse;

  factory CoachClientsResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachClientsResponseFromJson(json);
}

@freezed
abstract class TitleRef with _$TitleRef {
  const factory TitleRef({
    int? id,
    @Default('') String title,
    String? startDate,
    String? endDate,
  }) = _TitleRef;

  factory TitleRef.fromJson(Map<String, dynamic> json) =>
      _$TitleRefFromJson(json);
}

@freezed
abstract class CoachSubRef with _$CoachSubRef {
  const factory CoachSubRef({
    int? id,
    String? planName,
    String? status,
    String? endDate,
  }) = _CoachSubRef;

  factory CoachSubRef.fromJson(Map<String, dynamic> json) =>
      _$CoachSubRefFromJson(json);
}

@freezed
abstract class CoachRelationship with _$CoachRelationship {
  const factory CoachRelationship({
    String? relationshipType,
    String? status,
    String? startDate,
  }) = _CoachRelationship;

  factory CoachRelationship.fromJson(Map<String, dynamic> json) =>
      _$CoachRelationshipFromJson(json);
}

@freezed
abstract class CoachClientDetailDto with _$CoachClientDetailDto {
  const factory CoachClientDetailDto({
    required CoachClient client,
    CoachRelationship? relationship,
    TitleRef? activeWorkout,
    TitleRef? activePlan,
    CoachSubRef? subscription,
    String? lastCheckAt,
    @Default(0) int pendingChecks,
    int? conversationId,
  }) = _CoachClientDetailDto;

  factory CoachClientDetailDto.fromJson(Map<String, dynamic> json) =>
      _$CoachClientDetailDtoFromJson(json);
}

// ── Checks ──

@freezed
abstract class CoachCheckRow with _$CoachCheckRow {
  const factory CoachCheckRow({
    required int id,
    @Default('') String title,
    String? submittedAt,
    String? dueDate,
    @Default(false) bool reviewed,
    CoachClient? client,
    String? status,
  }) = _CoachCheckRow;

  factory CoachCheckRow.fromJson(Map<String, dynamic> json) =>
      _$CoachCheckRowFromJson(json);
}

@freezed
abstract class CoachChecksResponse with _$CoachChecksResponse {
  const factory CoachChecksResponse({
    @Default([]) List<CoachCheckRow> checks,
    @Default(false) bool hasMore,
  }) = _CoachChecksResponse;

  factory CoachChecksResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachChecksResponseFromJson(json);
}

@freezed
abstract class CoachCheckTemplate with _$CoachCheckTemplate {
  const CoachCheckTemplate._();
  const factory CoachCheckTemplate({
    required int id,
    @Default('') String title,
    @Default('') String description,
    @Default('') String presetKey,
    @Default(false) bool isModifiedPreset,
    @Default('') String questionnaireType,
    @Default(0) int questionsCount,
    @Default(0) int stepsCount,
    String? updatedAt,
  }) = _CoachCheckTemplate;

  factory CoachCheckTemplate.fromJson(Map<String, dynamic> json) =>
      _$CoachCheckTemplateFromJson(json);

  bool get isPreset => presetKey.isNotEmpty;
}

@freezed
abstract class CoachCheckTemplatesResponse
    with _$CoachCheckTemplatesResponse {
  const factory CoachCheckTemplatesResponse({
    @Default([]) List<CoachCheckTemplate> presets,
    @Default([]) List<CoachCheckTemplate> customs,
  }) = _CoachCheckTemplatesResponse;

  factory CoachCheckTemplatesResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachCheckTemplatesResponseFromJson(json);
}

/// Template detail: the raw builder config (steps + questions JSON).
@freezed
abstract class CoachCheckTemplateDetail with _$CoachCheckTemplateDetail {
  const factory CoachCheckTemplateDetail({
    required int id,
    @Default('') String title,
    @Default('') String description,
    @Default([]) List<Map<String, dynamic>> steps,
    @Default([]) List<Map<String, dynamic>> questions,
  }) = _CoachCheckTemplateDetail;

  factory CoachCheckTemplateDetail.fromJson(Map<String, dynamic> json) =>
      _$CoachCheckTemplateDetailFromJson(json);
}

@freezed
abstract class CheckCatalogItem with _$CheckCatalogItem {
  const factory CheckCatalogItem({
    required String key,
    required String label,
    String? group,
  }) = _CheckCatalogItem;

  factory CheckCatalogItem.fromJson(Map<String, dynamic> json) =>
      _$CheckCatalogItemFromJson(json);
}

@freezed
abstract class CheckCatalog with _$CheckCatalog {
  const factory CheckCatalog({
    @Default([]) List<CheckCatalogItem> circumferences,
    @Default([]) List<CheckCatalogItem> skinfolds,
  }) = _CheckCatalog;

  factory CheckCatalog.fromJson(Map<String, dynamic> json) =>
      _$CheckCatalogFromJson(json);
}

@freezed
abstract class CoachCheckPhoto with _$CoachCheckPhoto {
  const factory CoachCheckPhoto({
    required int id,
    required String url,
    String? type,
  }) = _CoachCheckPhoto;

  factory CoachCheckPhoto.fromJson(Map<String, dynamic> json) =>
      _$CoachCheckPhotoFromJson(json);
}

/// Submitted check as the coach reviews it. `sections` reuses the athlete
/// wire shape (same server serializer family).
@freezed
abstract class CoachCheckDetailDto with _$CoachCheckDetailDto {
  const factory CoachCheckDetailDto({
    required int id,
    @Default('') String title,
    String? submittedAt,
    CoachClient? client,
    @Default([]) List<Map<String, dynamic>> sections,
    @Default([]) List<CoachCheckPhoto> photos,
    String? notes,
    String? injuries,
    String? limitations,
    @Default('') String coachFeedback,
    double? weightKg,
    double? weightDelta,
  }) = _CoachCheckDetailDto;

  factory CoachCheckDetailDto.fromJson(Map<String, dynamic> json) =>
      _$CoachCheckDetailDtoFromJson(json);
}

@freezed
abstract class CoachCheckDetailResponse with _$CoachCheckDetailResponse {
  const factory CoachCheckDetailResponse({
    required CoachCheckDetailDto check,
  }) = _CoachCheckDetailResponse;

  factory CoachCheckDetailResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachCheckDetailResponseFromJson(json);
}

// ── Folders (workout/nutrition/check taxonomy) ──

@freezed
abstract class CoachFolder with _$CoachFolder {
  const CoachFolder._();
  const factory CoachFolder({
    required int id,
    @Default('') String title,
    String? labelText,
    String? labelColor,
    @Default(0) int order,
    @Default(0) int count,
  }) = _CoachFolder;

  factory CoachFolder.fromJson(Map<String, dynamic> json) =>
      _$CoachFolderFromJson(json);

  /// The auto-created, undeletable "Template" folder.
  bool get isDefaultTemplates => title == 'Template';
}

// ── Plans (library rows) ──

@freezed
abstract class CoachPlanRow with _$CoachPlanRow {
  const factory CoachPlanRow({
    required int id,
    @Default('') String title,
    String? status,
    String? goal,
    String? level,
    int? daysCount,
    int? durationWeeks,
    String? planKind,
    String? planMode,
    String? updatedAt,
    int? assignedCount,
  }) = _CoachPlanRow;

  factory CoachPlanRow.fromJson(Map<String, dynamic> json) =>
      _$CoachPlanRowFromJson(json);
}

@freezed
abstract class CoachAssignmentRow with _$CoachAssignmentRow {
  const factory CoachAssignmentRow({
    required int id,
    @Default('') String planTitle,
    CoachClient? client,
    String? startDate,
    String? endDate,
    String? status,
  }) = _CoachAssignmentRow;

  factory CoachAssignmentRow.fromJson(Map<String, dynamic> json) =>
      _$CoachAssignmentRowFromJson(json);
}

@freezed
abstract class CoachWorkoutsResponse with _$CoachWorkoutsResponse {
  const factory CoachWorkoutsResponse({
    @Default([]) List<CoachPlanRow> plans,
    @Default([]) List<CoachAssignmentRow> assignments,
    @Default([]) List<CoachFolder> folders,
    @Default(false) bool hasMore,
  }) = _CoachWorkoutsResponse;

  factory CoachWorkoutsResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachWorkoutsResponseFromJson(json);
}

// ── Subscriptions ──

@freezed
abstract class CoachSubscriptionPlanRow with _$CoachSubscriptionPlanRow {
  const factory CoachSubscriptionPlanRow({
    required int id,
    required String name,
    @Default(0) double price,
    @Default('EUR') String currency,
    String? kind,
    String? billingInterval,
    int? durationDays,
    String? description,
    @Default(true) bool isActive,
    @Default(0) int subscribersCount,
  }) = _CoachSubscriptionPlanRow;

  factory CoachSubscriptionPlanRow.fromJson(Map<String, dynamic> json) =>
      _$CoachSubscriptionPlanRowFromJson(json);
}

@freezed
abstract class CoachSubscriptionRow with _$CoachSubscriptionRow {
  const factory CoachSubscriptionRow({
    required int id,
    CoachClient? client,
    String? planName,
    String? status,
    String? startDate,
    String? endDate,
    double? price,
    String? paymentStatus,
  }) = _CoachSubscriptionRow;

  factory CoachSubscriptionRow.fromJson(Map<String, dynamic> json) =>
      _$CoachSubscriptionRowFromJson(json);
}

@freezed
abstract class CoachSubscriptionsDto with _$CoachSubscriptionsDto {
  const factory CoachSubscriptionsDto({
    @Default([]) List<CoachSubscriptionPlanRow> plans,
    @Default([]) List<CoachSubscriptionRow> subscriptions,
    double? monthlyRevenue,
    int? activeCount,
    @Default(false) bool hasMore,
  }) = _CoachSubscriptionsDto;

  factory CoachSubscriptionsDto.fromJson(Map<String, dynamic> json) =>
      _$CoachSubscriptionsDtoFromJson(json);
}

// ── Resources ──

@freezed
abstract class CoachResourceItem with _$CoachResourceItem {
  const factory CoachResourceItem({
    required int id,
    @Default('') String title,
    String? subtitle,
  }) = _CoachResourceItem;

  factory CoachResourceItem.fromJson(Map<String, dynamic> json) =>
      _$CoachResourceItemFromJson(json);
}

@freezed
abstract class CoachResourceSection with _$CoachResourceSection {
  const factory CoachResourceSection({
    required String key,
    @Default('') String title,
    @Default(0) int count,
    @Default([]) List<CoachResourceItem> items,
  }) = _CoachResourceSection;

  factory CoachResourceSection.fromJson(Map<String, dynamic> json) =>
      _$CoachResourceSectionFromJson(json);
}

@freezed
abstract class CoachResourcesResponse with _$CoachResourcesResponse {
  const factory CoachResourcesResponse({
    @Default([]) List<CoachResourceSection> sections,
  }) = _CoachResourcesResponse;

  factory CoachResourcesResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachResourcesResponseFromJson(json);
}

// ── Analytics ──

@freezed
abstract class CoachWeekPoint with _$CoachWeekPoint {
  const factory CoachWeekPoint({
    @Default('') String label,
    @Default(0) double value,
  }) = _CoachWeekPoint;

  factory CoachWeekPoint.fromJson(Map<String, dynamic> json) =>
      _$CoachWeekPointFromJson(json);
}

@freezed
abstract class CoachAnalyticsDto with _$CoachAnalyticsDto {
  const factory CoachAnalyticsDto({
    @Default(0) int activeClients,
    @Default(0) int pendingChecks,
    @Default(0) double reviewRate,
    @Default([]) List<CoachWeekPoint> checksPerWeek,
  }) = _CoachAnalyticsDto;

  factory CoachAnalyticsDto.fromJson(Map<String, dynamic> json) =>
      _$CoachAnalyticsDtoFromJson(json);
}

/// Business KPIs (`GET /api/v1/coach/analytics/business`).
@freezed
abstract class CoachBusinessKpis with _$CoachBusinessKpis {
  const factory CoachBusinessKpis({
    @Default(0) int activeClientsCount,
    @Default(0) int atRiskClientsCount,
    @Default(0) int renewalsDue7d,
    double? churnRate30d,
    double? monthlyRevenue,
    double? revenuePerActiveClient,
    double? slaAdherenceRate,
    @Default(0) int backlogOpenReviews,
  }) = _CoachBusinessKpis;

  factory CoachBusinessKpis.fromJson(Map<String, dynamic> json) =>
      _$CoachBusinessKpisFromJson(json);
}

@freezed
abstract class CoachBusinessDto with _$CoachBusinessDto {
  const factory CoachBusinessDto({
    required CoachBusinessKpis kpis,
  }) = _CoachBusinessDto;

  factory CoachBusinessDto.fromJson(Map<String, dynamic> json) =>
      _$CoachBusinessDtoFromJson(json);
}

@freezed
abstract class CoachRiskReason with _$CoachRiskReason {
  const factory CoachRiskReason({
    @Default('') String label,
  }) = _CoachRiskReason;

  factory CoachRiskReason.fromJson(Map<String, dynamic> json) =>
      _$CoachRiskReasonFromJson(json);
}

@freezed
abstract class CoachRiskClient with _$CoachRiskClient {
  const factory CoachRiskClient({
    required int id,
    @Default('') String displayName,
    String? profileImageUrl,
    double? riskScore,
    /// low | medium | high
    @Default('low') String riskClass,
    double? riskProbabilityMl,
    @Default([]) List<CoachRiskReason> reasons,
  }) = _CoachRiskClient;

  factory CoachRiskClient.fromJson(Map<String, dynamic> json) =>
      _$CoachRiskClientFromJson(json);
}

@freezed
abstract class CoachRiskResponse with _$CoachRiskResponse {
  const factory CoachRiskResponse({
    @Default([]) List<CoachRiskClient> clients,
    @Default(false) bool hasMore,
  }) = _CoachRiskResponse;

  factory CoachRiskResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachRiskResponseFromJson(json);
}

// ── Messaging ──

@freezed
abstract class CoachConversation with _$CoachConversation {
  const factory CoachConversation({
    required int id,
    CoachClient? client,
    String? lastMessage,
    String? lastMessageAt,
    @Default(0) int unreadCount,
  }) = _CoachConversation;

  factory CoachConversation.fromJson(Map<String, dynamic> json) =>
      _$CoachConversationFromJson(json);
}

@freezed
abstract class CoachConversationsResponse
    with _$CoachConversationsResponse {
  const factory CoachConversationsResponse({
    @Default([]) List<CoachConversation> conversations,
  }) = _CoachConversationsResponse;

  factory CoachConversationsResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachConversationsResponseFromJson(json);
}

@freezed
abstract class CoachAutoMessage with _$CoachAutoMessage {
  const factory CoachAutoMessage({
    required String key,
    @Default('') String label,
    @Default('') String body,
    @Default(false) bool enabled,
  }) = _CoachAutoMessage;

  factory CoachAutoMessage.fromJson(Map<String, dynamic> json) =>
      _$CoachAutoMessageFromJson(json);
}

@freezed
abstract class CoachAutoMessagesResponse with _$CoachAutoMessagesResponse {
  const factory CoachAutoMessagesResponse({
    @Default([]) List<CoachAutoMessage> templates,
  }) = _CoachAutoMessagesResponse;

  factory CoachAutoMessagesResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachAutoMessagesResponseFromJson(json);
}

@freezed
abstract class CoachMessageableClient with _$CoachMessageableClient {
  const factory CoachMessageableClient({
    required int id,
    @Default('') String displayName,
    String? profileImageUrl,
  }) = _CoachMessageableClient;

  factory CoachMessageableClient.fromJson(Map<String, dynamic> json) =>
      _$CoachMessageableClientFromJson(json);
}

@freezed
abstract class CoachStartConversationResponse
    with _$CoachStartConversationResponse {
  const factory CoachStartConversationResponse({
    required int conversationId,
  }) = _CoachStartConversationResponse;

  factory CoachStartConversationResponse.fromJson(
          Map<String, dynamic> json) =>
      _$CoachStartConversationResponseFromJson(json);
}

// ── Supplements (coach management) ──

@freezed
abstract class CoachSupplementSummary with _$CoachSupplementSummary {
  const factory CoachSupplementSummary({
    required int id,
    @Default('') String title,
    String? notes,
    @Default(0) int itemsCount,
    @Default(0) int assignedCount,
  }) = _CoachSupplementSummary;

  factory CoachSupplementSummary.fromJson(Map<String, dynamic> json) =>
      _$CoachSupplementSummaryFromJson(json);
}

@freezed
abstract class CoachSupplementsResponse with _$CoachSupplementsResponse {
  const factory CoachSupplementsResponse({
    @Default([]) List<CoachSupplementSummary> protocols,
  }) = _CoachSupplementsResponse;

  factory CoachSupplementsResponse.fromJson(Map<String, dynamic> json) =>
      _$CoachSupplementsResponseFromJson(json);
}

@freezed
abstract class CoachSupplementItem with _$CoachSupplementItem {
  const factory CoachSupplementItem({
    int? id,
    @Default('') String name,
    String? quantity,
    String? unit,
    String? timing,
    String? notes,
  }) = _CoachSupplementItem;

  factory CoachSupplementItem.fromJson(Map<String, dynamic> json) =>
      _$CoachSupplementItemFromJson(json);
}

@freezed
abstract class CoachSupplementDetail with _$CoachSupplementDetail {
  const factory CoachSupplementDetail({
    required int id,
    @Default('') String title,
    String? notes,
    @Default([]) List<CoachSupplementItem> items,
  }) = _CoachSupplementDetail;

  factory CoachSupplementDetail.fromJson(Map<String, dynamic> json) =>
      _$CoachSupplementDetailFromJson(json);
}

@freezed
abstract class CoachAssignableClient with _$CoachAssignableClient {
  const factory CoachAssignableClient({
    required int id,
    @Default('') String displayName,
    String? profileImageUrl,
    Map<String, dynamic>? activeProtocol,
    Map<String, dynamic>? activeAssignment,
  }) = _CoachAssignableClient;

  factory CoachAssignableClient.fromJson(Map<String, dynamic> json) =>
      _$CoachAssignableClientFromJson(json);
}

// ── Client progress (native charts) ──

@freezed
abstract class CoachProgressKpiDto with _$CoachProgressKpiDto {
  const factory CoachProgressKpiDto({
    @Default(0) int totalSessions,
    @Default(0) double avgSetsPerSession,
    @Default(0) int streakDays,
    double? overallAdherencePct,
  }) = _CoachProgressKpiDto;

  factory CoachProgressKpiDto.fromJson(Map<String, dynamic> json) =>
      _$CoachProgressKpiDtoFromJson(json);
}

@freezed
abstract class AdherencePointDto with _$AdherencePointDto {
  const factory AdherencePointDto({
    @Default('') String label,
    @Default(0) int done,
    @Default(0) int target,
  }) = _AdherencePointDto;

  factory AdherencePointDto.fromJson(Map<String, dynamic> json) =>
      _$AdherencePointDtoFromJson(json);
}

@freezed
abstract class RpePointDto with _$RpePointDto {
  const factory RpePointDto({
    String? date,
    double? value,
  }) = _RpePointDto;

  factory RpePointDto.fromJson(Map<String, dynamic> json) =>
      _$RpePointDtoFromJson(json);
}

// ── Chiron AI (coach-only chat) ──

@freezed
abstract class ChironMessageDto with _$ChironMessageDto {
  const factory ChironMessageDto({
    int? id,
    /// user | assistant
    @Default('assistant') String role,
    @Default('') String content,
    List<Map<String, dynamic>>? sources,
    List<Map<String, dynamic>>? actions,
    String? createdAt,
  }) = _ChironMessageDto;

  factory ChironMessageDto.fromJson(Map<String, dynamic> json) =>
      _$ChironMessageDtoFromJson(json);
}

@freezed
abstract class ChironHistoryResponse with _$ChironHistoryResponse {
  const factory ChironHistoryResponse({
    @Default([]) List<ChironMessageDto> messages,
    @Default(false) bool hasMore,
  }) = _ChironHistoryResponse;

  factory ChironHistoryResponse.fromJson(Map<String, dynamic> json) =>
      _$ChironHistoryResponseFromJson(json);
}
