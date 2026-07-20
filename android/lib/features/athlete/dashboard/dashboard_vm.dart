import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/cache/memory_cache.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/weekday.dart';

/// Dashboard state — port of iOS `DashboardVM`. Every fetch fails soft
/// (a blip renders as missing slice, not a blank screen); the dashboard's
/// base payload is cached 5 minutes.
@immutable
class DashboardState {
  const DashboardState({
    this.workouts = const [],
    this.nutrition = const [],
    this.conversations = const [],
    this.summary,
    this.loading = true,
    this.layoutWidgets = const [],
    this.catalog = const [],
    this.weights = const [],
    this.checksDue = const [],
  });

  final List<WorkoutPlanDto> workouts;
  final List<NutritionPlanDto> nutrition;
  final List<ConversationDto> conversations;
  final DashboardSummaryDto? summary;
  final bool loading;

  /// Customizable layout — array order is canonical (synced with web).
  final List<DashboardWidgetDto> layoutWidgets;
  final List<WidgetCatalogItemDto> catalog;

  /// Extra data fetched only when the matching widget is placed.
  final List<double> weights; // chronological
  final List<CheckDto> checksDue;

  DashboardState copyWith({
    List<WorkoutPlanDto>? workouts,
    List<NutritionPlanDto>? nutrition,
    List<ConversationDto>? conversations,
    DashboardSummaryDto? summary,
    bool? loading,
    List<DashboardWidgetDto>? layoutWidgets,
    List<WidgetCatalogItemDto>? catalog,
    List<double>? weights,
    List<CheckDto>? checksDue,
  }) {
    return DashboardState(
      workouts: workouts ?? this.workouts,
      nutrition: nutrition ?? this.nutrition,
      conversations: conversations ?? this.conversations,
      summary: summary ?? this.summary,
      loading: loading ?? this.loading,
      layoutWidgets: layoutWidgets ?? this.layoutWidgets,
      catalog: catalog ?? this.catalog,
      weights: weights ?? this.weights,
      checksDue: checksDue ?? this.checksDue,
    );
  }

  int get sessionsThisWeek => summary?.sessionsThisWeek ?? 0;

  String get kcalTargetDisplay {
    final k = summary?.kcalTarget;
    if (k == null || k <= 0) return '—';
    return k.toInt().toString();
  }

  String get daysToRenewalDisplay =>
      summary?.daysToRenewal?.toString() ?? '—';

  String get weightCurrentDisplay {
    final w = summary?.weightCurrent;
    return w == null ? '—' : w.toStringAsFixed(1);
  }

  /// First session of the active plan, shown as "today's" workout.
  WorkoutDayDto? get todayDay =>
      workouts.isEmpty || workouts.first.days.isEmpty
          ? null
          : workouts.first.days.first;

  /// The active FOOD plan (MACRO plans have no meal list).
  NutritionPlanDto? get nextMealPlan {
    for (final p in nutrition) {
      if (p.planMode != 'MACRO') return p;
    }
    return null;
  }

  List<MealDto> get todaysMeals {
    final plan = nextMealPlan;
    if (plan == null) return const [];
    final todayCode = DietWeekday.fromDate(DateTime.now()).code;
    for (final d in plan.days) {
      if (d.dayOfWeek.toUpperCase() == todayCode) return d.meals;
    }
    return plan.days.isEmpty ? const [] : plan.days.first.meals;
  }

  MealDto? get nextMeal => todaysMeals.isEmpty ? null : todaysMeals.first;

  ConversationDto? get lastConversation =>
      conversations.isEmpty ? null : conversations.first;
}

final dashboardVmProvider =
    NotifierProvider<DashboardVm, DashboardState>(DashboardVm.new);

class DashboardVm extends Notifier<DashboardState> {
  bool _isLoading = false;
  Timer? _saveTimer;

  @override
  DashboardState build() {
    ref.onDispose(() => _saveTimer?.cancel());
    return const DashboardState();
  }

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      final cache = ref.read(memoryCacheProvider);
      if (!force) {
        final w = cache.get<List<WorkoutPlanDto>>(CacheKeys.dashboardWorkouts);
        final n =
            cache.get<List<NutritionPlanDto>>(CacheKeys.dashboardNutrition);
        final v = cache
            .get<List<ConversationDto>>(CacheKeys.dashboardConversations);
        final s = cache.get<DashboardSummaryDto>(CacheKeys.dashboardSummary);
        final l = cache.get<DashboardLayoutDto>(CacheKeys.dashboardLayout);
        final c =
            cache.get<List<WidgetCatalogItemDto>>(CacheKeys.dashboardCatalog);
        if (w != null &&
            n != null &&
            v != null &&
            s != null &&
            l != null &&
            c != null) {
          state = state.copyWith(
            workouts: w,
            nutrition: n,
            conversations: v,
            summary: s,
            layoutWidgets: l.widgets,
            catalog: c,
            loading: false,
          );
          await _loadWidgetExtras();
          return;
        }
      }
      state = state.copyWith(loading: true);
      final api = ref.read(apiClientProvider);
      final results = await Future.wait<Object?>([
        _soft(api.workouts()),
        _soft(api.nutrition()),
        _soft(api.conversations()),
        _soft(api.dashboardSummary()),
        _soft(api.dashboardLayout()),
      ]);
      final w = results[0] as List<WorkoutPlanDto>?;
      final n = results[1] as List<NutritionPlanDto>?;
      final v = results[2] as List<ConversationDto>?;
      final s = results[3] as DashboardSummaryDto?;
      final l = results[4] as DashboardLayoutResponse?;
      if (w != null) cache.set(CacheKeys.dashboardWorkouts, w);
      if (n != null) cache.set(CacheKeys.dashboardNutrition, n);
      if (v != null) cache.set(CacheKeys.dashboardConversations, v);
      if (s != null) cache.set(CacheKeys.dashboardSummary, s);
      if (l != null) {
        cache.set(CacheKeys.dashboardLayout, l.layout);
        cache.set(CacheKeys.dashboardCatalog, l.catalog);
      }
      state = state.copyWith(
        workouts: w ?? state.workouts,
        nutrition: n ?? state.nutrition,
        conversations: v ?? state.conversations,
        summary: s ?? state.summary,
        layoutWidgets: l?.layout.widgets ?? state.layoutWidgets,
        catalog: l?.catalog ?? state.catalog,
        loading: false,
      );
      await _loadWidgetExtras();
    } finally {
      _isLoading = false;
    }
  }

  static Future<T?> _soft<T>(Future<T> f) async {
    try {
      return await f;
    } catch (e) {
      debugPrint('DashboardVm.load slice failed: $e');
      return null;
    }
  }

  /// Data for widgets outside the classic payload — only when placed.
  Future<void> _loadWidgetExtras() async {
    final api = ref.read(apiClientProvider);
    final types = state.layoutWidgets.map((w) => w.type).toSet();
    if (types.contains('weight_trend') && state.weights.isEmpty) {
      final p = await _soft(api.progress());
      if (p != null) {
        final weights = p.entries
            .map((e) => e.weightKg)
            .whereType<double>()
            .toList()
            .reversed
            .toList();
        state = state.copyWith(weights: weights);
      }
    }
    if (types.contains('checks_due') && state.checksDue.isEmpty) {
      final c = await _soft(api.checks());
      if (c != null) state = state.copyWith(checksDue: c);
    }
  }

  /// Re-fetch just the layout (app resumed → pick up edits made on web).
  Future<void> refreshLayout() async {
    final api = ref.read(apiClientProvider);
    final resp = await _soft(api.dashboardLayout());
    if (resp == null) return;
    final cache = ref.read(memoryCacheProvider);
    cache.set(CacheKeys.dashboardLayout, resp.layout);
    cache.set(CacheKeys.dashboardCatalog, resp.catalog);
    state =
        state.copyWith(layoutWidgets: resp.layout.widgets, catalog: resp.catalog);
    await _loadWidgetExtras();
  }

  /// Replaces the widget list (edit sheet) and autosaves, debounced 600 ms
  /// (mirrors the web grid's debounce). `y` is rewritten to the array index
  /// so the web grid re-flows to this order.
  void setWidgets(List<DashboardWidgetDto> widgets) {
    final normalized = [
      for (final (i, w) in widgets.indexed) w.copyWith(y: i),
    ];
    state = state.copyWith(layoutWidgets: normalized);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () async {
      final api = ref.read(apiClientProvider);
      final resp = await _soft(api.updateDashboardLayout(
          DashboardLayoutDto(version: 1, widgets: state.layoutWidgets)));
      if (resp != null) {
        ref.read(memoryCacheProvider).set(CacheKeys.dashboardLayout, resp.layout);
      }
      unawaited(_loadWidgetExtras());
    });
  }

  Future<void> resetLayout() async {
    final api = ref.read(apiClientProvider);
    final resp = await _soft(api.resetDashboardLayout());
    if (resp == null) return;
    ref.read(memoryCacheProvider).set(CacheKeys.dashboardLayout, resp.layout);
    state = state.copyWith(layoutWidgets: resp.layout.widgets);
    await _loadWidgetExtras();
  }
}
