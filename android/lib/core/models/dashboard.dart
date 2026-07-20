import 'package:freezed_annotation/freezed_annotation.dart';

part 'dashboard.freezed.dart';
part 'dashboard.g.dart';

/// Dashboard KPIs — same numbers as the web dashboard tiles, computed
/// server-side by `_client_dashboard_kpis` so both surfaces always match.
@freezed
abstract class DashboardSummaryDto with _$DashboardSummaryDto {
  const factory DashboardSummaryDto({
    double? weightCurrent,
    double? weightDelta,
    @Default(0) int sessionsThisWeek,
    double? kcalTarget,
    int? daysToRenewal,
  }) = _DashboardSummaryDto;

  factory DashboardSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardSummaryDtoFromJson(json);
}

// ── Customizable dashboard layout (synced web ↔ mobile) ──

/// Per-widget options. v1 knows a single key (`client_ids` for the coach's
/// pinned-athletes widget).
@freezed
abstract class DashboardWidgetConfigDto with _$DashboardWidgetConfigDto {
  const factory DashboardWidgetConfigDto({
    List<int>? clientIds,
  }) = _DashboardWidgetConfigDto;

  factory DashboardWidgetConfigDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardWidgetConfigDtoFromJson(json);
}

/// One placed widget. `x`/`y`/`size` are the web grid's presentation hints —
/// mobile renders widgets in ARRAY ORDER (the canonical cross-platform order)
/// and, when reordering, rewrites `y = index` so the web grid re-flows.
@freezed
abstract class DashboardWidgetDto with _$DashboardWidgetDto {
  const factory DashboardWidgetDto({
    required String id,
    required String type,
    @Default(0) int x,
    @Default(0) int y,
    @Default('half') String size,
    DashboardWidgetConfigDto? config,
  }) = _DashboardWidgetDto;

  factory DashboardWidgetDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardWidgetDtoFromJson(json);
}

@freezed
abstract class DashboardLayoutDto with _$DashboardLayoutDto {
  const factory DashboardLayoutDto({
    @Default(1) int version,
    @Default([]) List<DashboardWidgetDto> widgets,
  }) = _DashboardLayoutDto;

  factory DashboardLayoutDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardLayoutDtoFromJson(json);
}

/// Catalog entry from the server registry (role-filtered).
@freezed
abstract class WidgetCatalogItemDto with _$WidgetCatalogItemDto {
  const factory WidgetCatalogItemDto({
    required String type,
    required String title,
    @Default('') String desc,
    @Default('') String sfSymbol,
    @Default('half') String mobileSize,
  }) = _WidgetCatalogItemDto;

  factory WidgetCatalogItemDto.fromJson(Map<String, dynamic> json) =>
      _$WidgetCatalogItemDtoFromJson(json);
}

@freezed
abstract class DashboardLayoutResponse with _$DashboardLayoutResponse {
  const factory DashboardLayoutResponse({
    required DashboardLayoutDto layout,
    @Default([]) List<WidgetCatalogItemDto> catalog,
  }) = _DashboardLayoutResponse;

  factory DashboardLayoutResponse.fromJson(Map<String, dynamic> json) =>
      _$DashboardLayoutResponseFromJson(json);
}

/// Row of the coach's "Atleti in evidenza" widget.
@freezed
abstract class PinnedAthleteDto with _$PinnedAthleteDto {
  const factory PinnedAthleteDto({
    required int id,
    @Default('') String firstName,
    @Default('') String lastName,
    @Default('') String displayName,
    String? profileImageUrl,
    String? sport,
    String? lastCheckAt,
    double? weightDelta,
    @Default(false) bool hasPendingCheck,
  }) = _PinnedAthleteDto;

  factory PinnedAthleteDto.fromJson(Map<String, dynamic> json) =>
      _$PinnedAthleteDtoFromJson(json);
}

@freezed
abstract class PinnedAthletesResponse with _$PinnedAthletesResponse {
  const factory PinnedAthletesResponse({
    @Default([]) List<PinnedAthleteDto> athletes,
  }) = _PinnedAthletesResponse;

  factory PinnedAthletesResponse.fromJson(Map<String, dynamic> json) =>
      _$PinnedAthletesResponseFromJson(json);
}
