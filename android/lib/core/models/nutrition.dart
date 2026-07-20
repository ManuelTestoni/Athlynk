import 'package:freezed_annotation/freezed_annotation.dart';

import 'auth.dart';

part 'nutrition.freezed.dart';
part 'nutrition.g.dart';

/// Athlete-facing meal item — JSON key `carbs` (plural), backed by
/// `config/api.py`. The coach counterpart (`CoachMealItemDto`) is backed by a
/// different serializer and uses `carb` (singular). Both are correct for
/// their own endpoints — don't unify without changing the backend too.
@freezed
abstract class MealItemDto with _$MealItemDto {
  const factory MealItemDto({
    required int id,
    String? name,
    @Default(0) double quantityG,
    @Default(0) double kcal,
    @Default(0) double protein,
    @Default(0) double carbs,
    @Default(0) double fat,
  }) = _MealItemDto;

  factory MealItemDto.fromJson(Map<String, dynamic> json) =>
      _$MealItemDtoFromJson(json);
}

@freezed
abstract class MealDto with _$MealDto {
  const MealDto._();
  const factory MealDto({
    required int id,
    required String name,
    String? timeOfDay,
    @Default([]) List<MealItemDto> items,
  }) = _MealDto;

  factory MealDto.fromJson(Map<String, dynamic> json) => _$MealDtoFromJson(json);

  double get kcal => items.fold(0, (sum, i) => sum + i.kcal);
}

@freezed
abstract class DietDayDto with _$DietDayDto {
  const factory DietDayDto({
    required int id,
    required String dayOfWeek,
    int? targetKcal,
    int? targetProteinG,
    int? targetCarbG,
    int? targetFatG,
    @Default([]) List<MealDto> meals,
  }) = _DietDayDto;

  factory DietDayDto.fromJson(Map<String, dynamic> json) =>
      _$DietDayDtoFromJson(json);
}

/// Plan-level overview macro targets.
typedef OverviewTargets = ({int kcal, int? protein, int? carb, int? fat});

@freezed
abstract class NutritionPlanDto with _$NutritionPlanDto {
  const NutritionPlanDto._();
  const factory NutritionPlanDto({
    required int assignmentId,
    required int planId,
    required String title,
    /// FOOD | MACRO
    @Default('FOOD') String planMode,
    /// DAILY | WEEKLY
    @Default('DAILY') String planKind,
    String? nutritionGoal,
    int? dailyKcal,
    int? proteinTargetG,
    int? carbTargetG,
    int? fatTargetG,
    Coach? coach,
    @Default([]) List<DietDayDto> days,
  }) = _NutritionPlanDto;

  factory NutritionPlanDto.fromJson(Map<String, dynamic> json) =>
      _$NutritionPlanDtoFromJson(json);

  int get id => assignmentId;
  bool get isMacro => planMode == 'MACRO';
  bool get isWeekly => planKind == 'WEEKLY';

  /// Plan-level overview targets (matches the web plan summary card, not a
  /// single day). MACRO plans without a plan-level daily target fall back to
  /// the week's average, same as web `_plan_macro_targets(plan)['avg']`.
  OverviewTargets get overviewTargets {
    final k = dailyKcal;
    if (k != null && k > 0) {
      return (kcal: k, protein: proteinTargetG, carb: carbTargetG, fat: fatTargetG);
    }
    if (planMode == 'MACRO') {
      int? avg(int? Function(DietDayDto) f) {
        final vals = days.map(f).whereType<int>().toList();
        if (vals.isEmpty) return null;
        return vals.reduce((a, b) => a + b) ~/ vals.length;
      }

      return (
        kcal: avg((d) => d.targetKcal) ?? 0,
        protein: avg((d) => d.targetProteinG),
        carb: avg((d) => d.targetCarbG),
        fat: avg((d) => d.targetFatG),
      );
    }
    final kcalFirstDay =
        days.isEmpty ? 0.0 : days.first.meals.fold(0.0, (s, m) => s + m.kcal);
    return (
      kcal: kcalFirstDay.toInt(),
      protein: proteinTargetG,
      carb: carbTargetG,
      fat: fatTargetG,
    );
  }
}

@freezed
abstract class NutritionResponse with _$NutritionResponse {
  const factory NutritionResponse({
    @Default([]) List<NutritionPlanDto> plans,
  }) = _NutritionResponse;

  factory NutritionResponse.fromJson(Map<String, dynamic> json) =>
      _$NutritionResponseFromJson(json);
}

// ── MACRO-mode food logging ──

@freezed
abstract class FoodDto with _$FoodDto {
  const factory FoodDto({
    required int id,
    required String name,
    String? category,
    // per 100 g
    @Default(0) double kcal,
    @Default(0) double protein,
    @Default(0) double carb,
    @Default(0) double fat,
  }) = _FoodDto;

  factory FoodDto.fromJson(Map<String, dynamic> json) => _$FoodDtoFromJson(json);
}

/// Athlete-facing macro totals. Coach counterpart adds a `micros` field.
@freezed
abstract class MacroMacrosDto with _$MacroMacrosDto {
  const factory MacroMacrosDto({
    @Default(0) double kcal,
    @Default(0) double protein,
    @Default(0) double carb,
    @Default(0) double fat,
  }) = _MacroMacrosDto;

  factory MacroMacrosDto.fromJson(Map<String, dynamic> json) =>
      _$MacroMacrosDtoFromJson(json);
}

@freezed
abstract class MacroEntryDto with _$MacroEntryDto {
  const factory MacroEntryDto({
    required int id,
    required String name,
    @Default('') String mealName,
    @Default(0) double quantityG,
    @Default(0) double kcal,
    @Default(0) double protein,
    @Default(0) double carbs,
    @Default(0) double fat,
  }) = _MacroEntryDto;

  factory MacroEntryDto.fromJson(Map<String, dynamic> json) =>
      _$MacroEntryDtoFromJson(json);
}

@freezed
abstract class MacroDayDto with _$MacroDayDto {
  const factory MacroDayDto({
    required String date,
    required MacroMacrosDto target,
    required MacroMacrosDto consumed,
    @Default([]) List<MacroEntryDto> entries,
  }) = _MacroDayDto;

  factory MacroDayDto.fromJson(Map<String, dynamic> json) =>
      _$MacroDayDtoFromJson(json);
}

@freezed
abstract class FoodSearchResponse with _$FoodSearchResponse {
  const factory FoodSearchResponse({
    @Default([]) List<FoodDto> results,
    List<String>? categories,
  }) = _FoodSearchResponse;

  factory FoodSearchResponse.fromJson(Map<String, dynamic> json) =>
      _$FoodSearchResponseFromJson(json);
}

@freezed
abstract class MacroDayResponse with _$MacroDayResponse {
  const factory MacroDayResponse({
    required MacroDayDto macroDay,
  }) = _MacroDayResponse;

  factory MacroDayResponse.fromJson(Map<String, dynamic> json) =>
      _$MacroDayResponseFromJson(json);
}

/// One past day of the athlete's compiled meal log.
@freezed
abstract class MacroHistoryDayDto with _$MacroHistoryDayDto {
  const factory MacroHistoryDayDto({
    /// ISO yyyy-MM-dd — stable id.
    required String date,
    /// LUN…DOM
    @Default('') String dowShort,
    required MacroMacrosDto target,
    required MacroMacrosDto consumed,
    @Default([]) List<MacroEntryDto> entries,
  }) = _MacroHistoryDayDto;

  factory MacroHistoryDayDto.fromJson(Map<String, dynamic> json) =>
      _$MacroHistoryDayDtoFromJson(json);
}

@freezed
abstract class MacroHistoryResponse with _$MacroHistoryResponse {
  const factory MacroHistoryResponse({
    @Default([]) List<MacroHistoryDayDto> days,
    @Default(false) bool hasMore,
  }) = _MacroHistoryResponse;

  factory MacroHistoryResponse.fromJson(Map<String, dynamic> json) =>
      _$MacroHistoryResponseFromJson(json);
}

// ── Supplements (Integratori) ──

@freezed
abstract class SupplementItemDto with _$SupplementItemDto {
  const SupplementItemDto._();
  const factory SupplementItemDto({
    required int id,
    required String name,
    String? quantity,
    String? unit,
    String? timing,
    String? notes,
  }) = _SupplementItemDto;

  factory SupplementItemDto.fromJson(Map<String, dynamic> json) =>
      _$SupplementItemDtoFromJson(json);

  /// "5 g" / "2 cps" — quantity + unit, blanks tolerated.
  String get dose =>
      [quantity ?? '', unit ?? ''].where((s) => s.isNotEmpty).join(' ');
}

@freezed
abstract class SupplementSheetDto with _$SupplementSheetDto {
  const factory SupplementSheetDto({
    required int id,
    required String title,
    String? notes,
    Coach? coach,
    @Default([]) List<SupplementItemDto> items,
  }) = _SupplementSheetDto;

  factory SupplementSheetDto.fromJson(Map<String, dynamic> json) =>
      _$SupplementSheetDtoFromJson(json);
}

@freezed
abstract class SupplementsResponse with _$SupplementsResponse {
  const factory SupplementsResponse({
    @Default([]) List<SupplementSheetDto> sheets,
    @Default(false) bool hasMore,
  }) = _SupplementsResponse;

  factory SupplementsResponse.fromJson(Map<String, dynamic> json) =>
      _$SupplementsResponseFromJson(json);
}
