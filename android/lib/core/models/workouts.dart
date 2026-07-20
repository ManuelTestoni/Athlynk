import 'package:freezed_annotation/freezed_annotation.dart';

import 'auth.dart';

part 'workouts.freezed.dart';
part 'workouts.g.dart';

/// Athlete-facing exercise shape. Coach counterpart: `CoachWorkoutExerciseDto`
/// — same backend resource, kept separate because the coach payload carries
/// editing-only fields. Keep field names in sync.
@freezed
abstract class ExerciseDto with _$ExerciseDto {
  const ExerciseDto._();
  const factory ExerciseDto({
    required int id,
    required String name,
    String? videoUrl,
    String? targetMuscleGroup,
    @Default([]) List<String> equipment,
    @Default(0) int orderIndex,
    int? setCount,
    int? repCount,
    String? repRange,
    int? rir,
    int? rpe,
    double? loadValue,
    String? loadUnit,
    int? recoverySeconds,
    String? tempo,
    String? techniqueNotes,
    int? supersetGroupId,
    // Catalog media/detail (exercises-dataset sourcing).
    @JsonKey(name: 'demo_gif') String? demoGif,
    @JsonKey(name: 'cover_image') String? coverImage,
    String? description,
    List<String>? instructionSteps,
    String? muscleDetail,
  }) = _ExerciseDto;

  factory ExerciseDto.fromJson(Map<String, dynamic> json) =>
      _$ExerciseDtoFromJson(json);

  /// "3×8-10" — sets × reps with em-dash fallbacks.
  String get setsReps {
    final s = setCount?.toString() ?? '—';
    final r = repRange ?? repCount?.toString() ?? '—';
    return '$s×$r';
  }

  /// "80 kg" / "75% 1RM" / "BW".
  String? get loadLabel {
    final v = loadValue;
    if (v == null) return null;
    final n = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    switch (loadUnit) {
      case 'PERCENT_1RM':
        return '$n% 1RM';
      case 'BODYWEIGHT':
        return 'BW';
      default:
        return '$n kg';
    }
  }
}

/// Athlete-facing workout day. Coach counterpart: `CoachWorkoutDayDto`.
@freezed
abstract class WorkoutDayDto with _$WorkoutDayDto {
  const WorkoutDayDto._();
  const factory WorkoutDayDto({
    required int id,
    required int dayOrder,
    String? dayName,
    String? title,
    String? focusArea,
    String? dayType,
    String? notes,
    @Default([]) List<ExerciseDto> exercises,
  }) = _WorkoutDayDto;

  factory WorkoutDayDto.fromJson(Map<String, dynamic> json) =>
      _$WorkoutDayDtoFromJson(json);

  String get label => title ?? dayName ?? 'Day $dayOrder';
}

/// Athlete-facing workout plan. Coach counterpart: `CoachWorkoutDetailDto`.
@freezed
abstract class WorkoutPlanDto with _$WorkoutPlanDto {
  const WorkoutPlanDto._();
  const factory WorkoutPlanDto({
    required int assignmentId,
    required int planId,
    required String title,
    String? description,
    String? goal,
    String? level,
    int? frequencyPerWeek,
    int? durationWeeks,
    String? startDate,
    Coach? coach,
    @Default([]) List<WorkoutDayDto> days,
  }) = _WorkoutPlanDto;

  factory WorkoutPlanDto.fromJson(Map<String, dynamic> json) =>
      _$WorkoutPlanDtoFromJson(json);

  int get id => assignmentId;
}

@freezed
abstract class WorkoutsResponse with _$WorkoutsResponse {
  const factory WorkoutsResponse({
    @Default([]) List<WorkoutPlanDto> plans,
  }) = _WorkoutsResponse;

  factory WorkoutsResponse.fromJson(Map<String, dynamic> json) =>
      _$WorkoutsResponseFromJson(json);
}

// ── Workout history (Storico Allenamenti) ──

@freezed
abstract class WorkoutSessionDto with _$WorkoutSessionDto {
  const factory WorkoutSessionDto({
    required int id,
    required String dayLabel,
    String? focusArea,
    String? startedAt,
    String? endedAt,
    int? durationMinutes,
    double? avgRpe,
    @Default(false) bool completed,
    @Default(false) bool interrupted,
    @Default(0) int setCount,
    String? notes,
  }) = _WorkoutSessionDto;

  factory WorkoutSessionDto.fromJson(Map<String, dynamic> json) =>
      _$WorkoutSessionDtoFromJson(json);
}

@freezed
abstract class WorkoutHistoryResponse with _$WorkoutHistoryResponse {
  const factory WorkoutHistoryResponse({
    @Default([]) List<WorkoutSessionDto> sessions,
    bool? hasMore,
  }) = _WorkoutHistoryResponse;

  factory WorkoutHistoryResponse.fromJson(Map<String, dynamic> json) =>
      _$WorkoutHistoryResponseFromJson(json);
}
