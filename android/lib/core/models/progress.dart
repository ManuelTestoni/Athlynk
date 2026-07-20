import 'package:freezed_annotation/freezed_annotation.dart';

part 'progress.freezed.dart';
part 'progress.g.dart';

@freezed
abstract class ProgressPhotoDto with _$ProgressPhotoDto {
  const factory ProgressPhotoDto({
    required int id,
    required String url,
    String? type,
    String? capturedAt,
  }) = _ProgressPhotoDto;

  factory ProgressPhotoDto.fromJson(Map<String, dynamic> json) =>
      _$ProgressPhotoDtoFromJson(json);
}

/// Athlete-facing progress-check entry. Coach counterpart `CoachProgressEntry`
/// is near-identical. Server sends measurement values as strings ("85.0");
/// empty sites are omitted.
@freezed
abstract class ProgressEntryDto with _$ProgressEntryDto {
  const factory ProgressEntryDto({
    required int id,
    String? submittedAt,
    double? weightKg,
    /// Circumferences in cm, keyed by site (waist, chest, …).
    Map<String, String>? measurements,
    /// Skinfolds in mm, keyed by site.
    Map<String, String>? skinfolds,
    String? coachFeedback,
    String? notes,
    @Default([]) List<ProgressPhotoDto> photos,
  }) = _ProgressEntryDto;

  factory ProgressEntryDto.fromJson(Map<String, dynamic> json) =>
      _$ProgressEntryDtoFromJson(json);
}

/// Site keys the client has ever recorded a value for.
@freezed
abstract class MeasurementSitesDto with _$MeasurementSitesDto {
  const factory MeasurementSitesDto({
    @Default([]) List<String> measurements,
    @Default([]) List<String> skinfolds,
  }) = _MeasurementSitesDto;

  factory MeasurementSitesDto.fromJson(Map<String, dynamic> json) =>
      _$MeasurementSitesDtoFromJson(json);
}

@freezed
abstract class ProgressResponse with _$ProgressResponse {
  const factory ProgressResponse({
    @Default([]) List<ProgressEntryDto> entries,
    @Default(false) bool hasMore,
  }) = _ProgressResponse;

  factory ProgressResponse.fromJson(Map<String, dynamic> json) =>
      _$ProgressResponseFromJson(json);
}

/// One selectable measurement site (e.g. "waist" → "Vita"). Limb
/// circumferences expose the two sides as separate options (`_l` / `_r`).
@freezed
abstract class MeasurementOption with _$MeasurementOption {
  const factory MeasurementOption({
    required String key,
    required String label,
  }) = _MeasurementOption;

  factory MeasurementOption.fromJson(Map<String, dynamic> json) =>
      _$MeasurementOptionFromJson(json);
}

@freezed
abstract class MeasurementCatalog with _$MeasurementCatalog {
  const factory MeasurementCatalog({
    @Default([]) List<MeasurementOption> circumferences,
    @Default([]) List<MeasurementOption> skinfolds,
  }) = _MeasurementCatalog;

  factory MeasurementCatalog.fromJson(Map<String, dynamic> json) =>
      _$MeasurementCatalogFromJson(json);
}

// ── "Il mio percorso" timeline ──

@freezed
abstract class JourneyEventDto with _$JourneyEventDto {
  const factory JourneyEventDto({
    required String id,
    /// allenamento | nutrizione | check
    required String type,
    /// ISO yyyy-MM-dd
    required String date,
    required String title,
    String? subtitle,
    String? statusLabel,
  }) = _JourneyEventDto;

  factory JourneyEventDto.fromJson(Map<String, dynamic> json) =>
      _$JourneyEventDtoFromJson(json);
}

@freezed
abstract class JourneyPhaseDto with _$JourneyPhaseDto {
  const factory JourneyPhaseDto({
    required int id,
    required String title,
    @Default('') String note,
    required String start,
    required String end,
    @Default(0) int durationValue,
    /// WEEKS | MONTHS
    @Default('WEEKS') String durationUnit,
  }) = _JourneyPhaseDto;

  factory JourneyPhaseDto.fromJson(Map<String, dynamic> json) =>
      _$JourneyPhaseDtoFromJson(json);
}

@freezed
abstract class JourneyResponse with _$JourneyResponse {
  const factory JourneyResponse({
    @Default([]) List<JourneyEventDto> events,
    @Default([]) List<JourneyPhaseDto> phases,
    @Default(false) bool hasMore,
  }) = _JourneyResponse;

  factory JourneyResponse.fromJson(Map<String, dynamic> json) =>
      _$JourneyResponseFromJson(json);
}
