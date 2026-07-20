import 'package:freezed_annotation/freezed_annotation.dart';

part 'session.freezed.dart';
part 'session.g.dart';

// ── Active session (Sessione Attiva) ──

/// Reference to a catalog exercise chosen as substitute for a plan slot.
@freezed
abstract class SubstituteExerciseDto with _$SubstituteExerciseDto {
  const factory SubstituteExerciseDto({
    required int id,
    required String name,
  }) = _SubstituteExerciseDto;

  factory SubstituteExerciseDto.fromJson(Map<String, dynamic> json) =>
      _$SubstituteExerciseDtoFromJson(json);
}

@freezed
abstract class SessionExerciseDto with _$SessionExerciseDto {
  const SessionExerciseDto._();
  const factory SessionExerciseDto({
    /// null for exercises added by the athlete during the session.
    int? workoutExerciseId,
    /// Catalog exercise id — set only for added exercises.
    int? exerciseId,
    /// Catalog id of the plan slot's exercise (for "similar to" lookups).
    int? exerciseCatalogId,
    required String name,
    String? targetMuscleGroup,
    @Default(3) int sets,
    @Default('10') String reps,
    double? loadValue,
    String? loadUnit,
    int? recoverySeconds,
    String? tempo,
    String? notes,
    @Default(false) bool added,
    @Default(false) bool removed,
    SubstituteExerciseDto? substitutedWith,
    /// Coach-prescribed targets — distinct from per-set logged RPE.
    int? rir,
    int? rpe,
    @JsonKey(name: 'cover_image') String? coverImage,
    @JsonKey(name: 'demo_gif') String? demoGif,
  }) = _SessionExerciseDto;

  factory SessionExerciseDto.fromJson(Map<String, dynamic> json) =>
      _$SessionExerciseDtoFromJson(json);

  /// Stable key matching `LoggedSetDto.exerciseKey`.
  String get key =>
      workoutExerciseId != null ? 'we-$workoutExerciseId' : 'add-${exerciseId ?? 0}';

  String get displayName => substitutedWith?.name ?? name;

  /// Local construction for exercises the athlete adds mid-session.
  factory SessionExerciseDto.addedExercise({
    required int catalogId,
    required String name,
    String? targetMuscleGroup,
    String? coverImage,
    String? demoGif,
  }) =>
      SessionExerciseDto(
        exerciseId: catalogId,
        exerciseCatalogId: catalogId,
        name: name,
        targetMuscleGroup: targetMuscleGroup,
        loadUnit: 'KG',
        recoverySeconds: 90,
        added: true,
        coverImage: coverImage,
        demoGif: demoGif,
      );
}

@freezed
abstract class LoggedSetDto with _$LoggedSetDto {
  const LoggedSetDto._();
  const factory LoggedSetDto({
    int? workoutExerciseId,
    /// Catalog exercise id for sets of added exercises.
    int? exerciseId,
    required int setNumber,
    int? repsDone,
    double? loadUsed,
    String? loadUnit,
    int? rpe,
    @Default(false) bool completed,
  }) = _LoggedSetDto;

  factory LoggedSetDto.fromJson(Map<String, dynamic> json) =>
      _$LoggedSetDtoFromJson(json);

  /// Matches `SessionExerciseDto.key`.
  String get exerciseKey =>
      workoutExerciseId != null ? 'we-$workoutExerciseId' : 'add-${exerciseId ?? 0}';
}

@freezed
abstract class SessionStartDto with _$SessionStartDto {
  const factory SessionStartDto({
    required int sessionId,
    @Default([]) List<SessionExerciseDto> exercises,
    @Default([]) List<LoggedSetDto> setsLogged,
    String? startedAt,
  }) = _SessionStartDto;

  factory SessionStartDto.fromJson(Map<String, dynamic> json) =>
      _$SessionStartDtoFromJson(json);
}

// ── Past session detail (athlete + coach share these) ──

/// Brief row for the coach's per-client session history list.
@freezed
abstract class SessionBriefDto with _$SessionBriefDto {
  const factory SessionBriefDto({
    required int id,
    String? dayName,
    String? startedAt,
    int? durationMinutes,
    double? avgRpe,
    @Default(false) bool completed,
    @Default(false) bool interrupted,
    String? notes,
  }) = _SessionBriefDto;

  factory SessionBriefDto.fromJson(Map<String, dynamic> json) =>
      _$SessionBriefDtoFromJson(json);
}

@freezed
abstract class SessionBriefListDto with _$SessionBriefListDto {
  const factory SessionBriefListDto({
    @Default([]) List<SessionBriefDto> sessions,
    bool? hasMore,
  }) = _SessionBriefListDto;

  factory SessionBriefListDto.fromJson(Map<String, dynamic> json) =>
      _$SessionBriefListDtoFromJson(json);
}

@freezed
abstract class LoggedSetDetailDto with _$LoggedSetDetailDto {
  const factory LoggedSetDetailDto({
    required int setNumber,
    int? repsDone,
    double? loadUsed,
    String? loadUnit,
    int? rpe,
    @Default(false) bool completed,
    @Default(false) bool exerciseSubstituted,
    SubstituteExerciseDto? actualExercise,
  }) = _LoggedSetDetailDto;

  factory LoggedSetDetailDto.fromJson(Map<String, dynamic> json) =>
      _$LoggedSetDetailDtoFromJson(json);
}

@freezed
abstract class SessionLoggedExerciseDto with _$SessionLoggedExerciseDto {
  const SessionLoggedExerciseDto._();
  const factory SessionLoggedExerciseDto({
    /// null for exercises added in-session (no plan slot).
    int? workoutExerciseId,
    required String exerciseName,
    String? exerciseNote,
    String? prescribedReps,
    @Default(false) bool added,
    @Default([]) List<LoggedSetDetailDto> sets,
  }) = _SessionLoggedExerciseDto;

  factory SessionLoggedExerciseDto.fromJson(Map<String, dynamic> json) =>
      _$SessionLoggedExerciseDtoFromJson(json);

  String get key =>
      workoutExerciseId != null ? 'we-$workoutExerciseId' : 'add-$exerciseName';

  /// Name of the movement actually performed (substituted sets carry it).
  String get performedName {
    for (final s in sets) {
      final a = s.actualExercise;
      if (a != null) return a.name;
    }
    return exerciseName;
  }

  bool get wasSubstituted => sets.any((s) => s.exerciseSubstituted);
}

@freezed
abstract class SessionDetailDto with _$SessionDetailDto {
  const factory SessionDetailDto({
    required int id,
    String? dayName,
    String? startedAt,
    int? durationMinutes,
    double? avgRpe,
    @Default(false) bool completed,
    @Default(false) bool interrupted,
    String? notes,
    @Default([]) List<SessionLoggedExerciseDto> exercises,
  }) = _SessionDetailDto;

  factory SessionDetailDto.fromJson(Map<String, dynamic> json) =>
      _$SessionDetailDtoFromJson(json);
}

// ── Exercise catalog search (add / substitute in session) ──

@freezed
abstract class ExerciseSearchItemDto with _$ExerciseSearchItemDto {
  const factory ExerciseSearchItemDto({
    required int id,
    required String name,
    @Default('') String primaryMuscle,
    @Default([]) List<String> muscles,
    @Default([]) List<String> equipment,
    String? videoUrl,
    @JsonKey(name: 'cover_image') String? coverImage,
    @JsonKey(name: 'demo_gif') String? demoGif,
    String? description,
  }) = _ExerciseSearchItemDto;

  factory ExerciseSearchItemDto.fromJson(Map<String, dynamic> json) =>
      _$ExerciseSearchItemDtoFromJson(json);
}

@freezed
abstract class MuscleGroupDto with _$MuscleGroupDto {
  const factory MuscleGroupDto({
    required String name,
    required String slug,
    @Default('') String region,
  }) = _MuscleGroupDto;

  factory MuscleGroupDto.fromJson(Map<String, dynamic> json) =>
      _$MuscleGroupDtoFromJson(json);
}

@freezed
abstract class ExerciseSearchResponse with _$ExerciseSearchResponse {
  const factory ExerciseSearchResponse({
    @Default([]) List<ExerciseSearchItemDto> results,
    List<MuscleGroupDto>? muscleGroups,
  }) = _ExerciseSearchResponse;

  factory ExerciseSearchResponse.fromJson(Map<String, dynamic> json) =>
      _$ExerciseSearchResponseFromJson(json);
}

// ── Exercise catalog detail (by id, dual-auth endpoint) ──

@freezed
abstract class ExerciseCatalogDetailDto with _$ExerciseCatalogDetailDto {
  const factory ExerciseCatalogDetailDto({
    required int id,
    required String name,
    String? description,
    @JsonKey(name: 'cover_image') String? coverImage,
    @JsonKey(name: 'demo_gif') String? demoGif,
    @Default([]) List<String> instructionSteps,
    String? muscleDetail,
    @Default(false) bool isCustom,
    ExerciseCatalogCategoryDto? category,
    @Default([]) List<ExerciseCatalogEquipmentDto> equipment,
    @Default([]) List<ExerciseCatalogMuscleDto> primaryMuscles,
    @Default([]) List<ExerciseCatalogMuscleDto> secondaryMuscles,
    String? coachNotes,
  }) = _ExerciseCatalogDetailDto;

  factory ExerciseCatalogDetailDto.fromJson(Map<String, dynamic> json) =>
      _$ExerciseCatalogDetailDtoFromJson(json);
}

@freezed
abstract class ExerciseCatalogCategoryDto with _$ExerciseCatalogCategoryDto {
  const factory ExerciseCatalogCategoryDto({
    required int id,
    required String name,
  }) = _ExerciseCatalogCategoryDto;

  factory ExerciseCatalogCategoryDto.fromJson(Map<String, dynamic> json) =>
      _$ExerciseCatalogCategoryDtoFromJson(json);
}

@freezed
abstract class ExerciseCatalogEquipmentDto with _$ExerciseCatalogEquipmentDto {
  const factory ExerciseCatalogEquipmentDto({
    required int id,
    required String name,
  }) = _ExerciseCatalogEquipmentDto;

  factory ExerciseCatalogEquipmentDto.fromJson(Map<String, dynamic> json) =>
      _$ExerciseCatalogEquipmentDtoFromJson(json);
}

@freezed
abstract class ExerciseCatalogMuscleDto with _$ExerciseCatalogMuscleDto {
  const factory ExerciseCatalogMuscleDto({
    required int id,
    required String slug,
    required String name,
    String? region,
    String? colorToken,
  }) = _ExerciseCatalogMuscleDto;

  factory ExerciseCatalogMuscleDto.fromJson(Map<String, dynamic> json) =>
      _$ExerciseCatalogMuscleDtoFromJson(json);
}

/// One row of the history-based progress list (movements ever performed).
@freezed
abstract class ExerciseHistoryItemDto with _$ExerciseHistoryItemDto {
  const factory ExerciseHistoryItemDto({
    required String name,
    String? lastDone,
    @Default(0) int sessionsCount,
  }) = _ExerciseHistoryItemDto;

  factory ExerciseHistoryItemDto.fromJson(Map<String, dynamic> json) =>
      _$ExerciseHistoryItemDtoFromJson(json);
}

@freezed
abstract class ExercisesHistoryResponse with _$ExercisesHistoryResponse {
  const factory ExercisesHistoryResponse({
    @Default([]) List<ExerciseHistoryItemDto> exercises,
  }) = _ExercisesHistoryResponse;

  factory ExercisesHistoryResponse.fromJson(Map<String, dynamic> json) =>
      _$ExercisesHistoryResponseFromJson(json);
}

// ── Exercise trend (per-session over time) — shared athlete & coach ──

@freezed
abstract class ExerciseTrendMeta with _$ExerciseTrendMeta {
  const factory ExerciseTrendMeta({
    required String name,
    @Default('KG') String loadUnit,
  }) = _ExerciseTrendMeta;

  factory ExerciseTrendMeta.fromJson(Map<String, dynamic> json) =>
      _$ExerciseTrendMetaFromJson(json);
}

@freezed
abstract class ExerciseTrendDto with _$ExerciseTrendDto {
  const factory ExerciseTrendDto({
    required ExerciseTrendMeta exercise,
    @Default(false) bool hasData,
    @Default([]) List<TrendSessionDto> sessions,
  }) = _ExerciseTrendDto;

  factory ExerciseTrendDto.fromJson(Map<String, dynamic> json) =>
      _$ExerciseTrendDtoFromJson(json);
}

@freezed
abstract class TrendSessionDto with _$TrendSessionDto {
  const factory TrendSessionDto({
    required int sessionId,
    String? date,
    double? avgRpe,
    double? volume,
    double? topSet,
    double? weightedAvgLoad,
    String? loadUnit,
    @Default([]) List<TrendSetDto> sets,
  }) = _TrendSessionDto;

  factory TrendSessionDto.fromJson(Map<String, dynamic> json) =>
      _$TrendSessionDtoFromJson(json);
}

@freezed
abstract class TrendSetDto with _$TrendSetDto {
  const factory TrendSetDto({
    required int setNumber,
    int? reps,
    double? load,
    double? rpe,
    bool? isExtra,
    String? actualExercise,
  }) = _TrendSetDto;

  factory TrendSetDto.fromJson(Map<String, dynamic> json) =>
      _$TrendSetDtoFromJson(json);
}
