import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/push/push_bridge.dart';
import '../../../core/utils/weekday.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import 'diet_day_detail_view.dart';
import 'macro_history_view.dart';
import 'macro_log_view.dart';
import 'meal_detail_view.dart';
import 'nutrition_plan_detail_view.dart';
import 'supplements_view.dart';

/// Fuel tab root — port of iOS `NutritionView`: plan cards + mode-specific
/// body (FOOD meal list / weekly carousel; MACRO diary links / weekly macro
/// strip) + supplements link.
class NutritionView extends ConsumerStatefulWidget {
  const NutritionView({super.key});

  @override
  ConsumerState<NutritionView> createState() => _NutritionViewState();
}

class _NutritionViewState extends ConsumerState<NutritionView> {
  List<NutritionPlanDto>? _plans;
  bool _error = false;
  StreamSubscription<String>? _remote;

  @override
  void initState() {
    super.initState();
    _load();
    _remote = ref.read(pushBridgeProvider).onTypes({
      RemoteChangeType.nutritionAssigned,
      RemoteChangeType.supplementAssigned,
    }).listen((_) => _load());
  }

  @override
  void dispose() {
    _remote?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final plans = await ref.read(apiClientProvider).nutrition();
      if (mounted) {
        setState(() {
          _plans = plans;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted && _plans == null) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    return ScreenScroll(
      onRefresh: _load,
      spacing: Space.element,
      children: [
        const ScreenHeader(eyebrow: 'Il tuo piano', title: 'Nutrizione'),
        if (plans == null && !_error)
          const ListCardsSkeleton(count: 2, height: 180)
        else if (_error)
          EmptyPanel.network(onCta: () {
            setState(() => _error = false);
            _load();
          })
        else if (plans!.isEmpty)
          const EmptyPanel(
            icon: Icons.restaurant_outlined,
            message:
                'Nessun piano nutrizionale attivo. Il tuo coach lo sta preparando.',
          )
        else
          for (final (i, plan) in plans.indexed) ...[
            RevealUp(index: i, child: _planCard(plan)),
            if (plan.isMacro) _macroBody(plan) else _foodBody(plan),
          ],
        NavListRow(
          title: 'Integratori',
          subtitle: 'Il tuo protocollo di integrazione',
          icon: Icons.medication_rounded,
          accent: Palette.lime,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const SupplementsView())),
        ),
      ],
    );
  }

  Widget _planCard(NutritionPlanDto plan) {
    final t = plan.overviewTargets;
    return VoltPanel(
      tint: Palette.lime.withValues(alpha: 0.4),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => NutritionPlanDetailView(plan: plan))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(plan.isMacro ? 'Macro' : 'Alimenti',
                  color: plan.isMacro ? Palette.cyan : Palette.lime),
              const SizedBox(width: 6),
              StatusBadge(plan.isWeekly ? 'Settimanale' : 'Giornaliero',
                  color: Palette.textLow),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Palette.textLow),
            ],
          ),
          const SizedBox(height: 10),
          Text(plan.title, style: Typo.display(21)),
          if ((plan.nutritionGoal ?? '').isNotEmpty)
            Text(plan.nutritionGoal!,
                style: Typo.body(13, FontWeight.w400, Palette.textMid)),
          const SizedBox(height: 12),
          Row(
            children: [
              _macroCol('${t.kcal}', 'kcal', Palette.amber),
              _macroCol('${t.protein ?? "—"}', 'prot', Palette.magenta),
              _macroCol('${t.carb ?? "—"}', 'carb', Palette.cyan),
              _macroCol('${t.fat ?? "—"}', 'grassi', Palette.lime),
            ],
          ),
          if (plan.coach != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 13, color: Palette.textLow),
                const SizedBox(width: 5),
                Text(plan.coach!.fullName,
                    style:
                        Typo.body(12, FontWeight.w600, Palette.textMid)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _macroCol(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: Typo.poster(19)),
          Text(label.toUpperCase(),
              style: Typo.mono(7.5, FontWeight.w700, color)
                  .copyWith(letterSpacing: 1)),
        ],
      ),
    );
  }

  // FOOD-mode body: today's meals (DAILY = flat list; WEEKLY = today first).
  Widget _foodBody(NutritionPlanDto plan) {
    final todayCode = DietWeekday.fromDate(DateTime.now()).code;
    DietDayDto? day;
    for (final d in plan.days) {
      if (d.dayOfWeek.toUpperCase() == todayCode) day = d;
    }
    day ??= plan.days.isEmpty ? null : plan.days.first;
    if (day == null) return const SizedBox.shrink();
    return Column(
      children: [
        if (plan.isWeekly)
          NavListRow(
            title: 'Giorni della settimana',
            subtitle: 'Sfoglia il piano giorno per giorno',
            icon: Icons.view_week_rounded,
            accent: Palette.lime,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    DietDayDetailView(plan: plan, initialDay: day!),
              ),
            ),
          ),
        const SizedBox(height: Space.element),
        for (final meal in day.meals)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.element),
            child: _mealRow(meal),
          ),
      ],
    );
  }

  Widget _mealRow(MealDto meal) {
    return VoltPanel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MealDetailView(meal: meal))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          const Icon(Icons.restaurant_rounded,
              size: 18, color: Palette.lime),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.name, style: Typo.body(15, FontWeight.w700)),
                Text(
                  '${meal.items.length} alimenti${(meal.timeOfDay ?? '').isEmpty ? '' : ' · ${meal.timeOfDay}'}',
                  style: Typo.body(12, FontWeight.w400, Palette.textMid),
                ),
              ],
            ),
          ),
          Text('${meal.kcal.toInt()} kcal',
              style: Typo.mono(12, FontWeight.w700, Palette.amber)),
        ],
      ),
    );
  }

  // MACRO-mode body: diary + history links (+ weekly target strip).
  Widget _macroBody(NutritionPlanDto plan) {
    return Column(
      children: [
        if (plan.isWeekly) _weeklyTargetStrip(plan),
        NavListRow(
          title: 'Diario di oggi',
          subtitle: 'Registra quello che mangi',
          icon: Icons.edit_note_rounded,
          accent: Palette.cyan,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => MacroLogView(assignmentId: plan.assignmentId))),
        ),
        const SizedBox(height: Space.element),
        NavListRow(
          title: 'Storico pasti',
          subtitle: 'I giorni già registrati',
          icon: Icons.calendar_view_day_rounded,
          accent: Palette.violet,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  MacroHistoryView(assignmentId: plan.assignmentId))),
        ),
      ],
    );
  }

  Widget _weeklyTargetStrip(NutritionPlanDto plan) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.element),
      child: SizedBox(
        height: 96,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final d in plan.days)
              Pressable(
                onTap: () {
                  final wd = DietWeekday.fromCode(d.dayOfWeek);
                  final date = wd?.dateInWeekOf(DateTime.now());
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => MacroLogView(
                      assignmentId: plan.assignmentId,
                      logDate: date,
                    ),
                  ));
                },
                child: Container(
                  width: 92,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: voltPanel(radius: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DietWeekday.fromCode(d.dayOfWeek)?.short ??
                            d.dayOfWeek,
                        style: Typo.mono(
                            10, FontWeight.w700, Palette.cyan),
                      ),
                      const SizedBox(height: 4),
                      Text('${d.targetKcal ?? "—"}',
                          style: Typo.poster(20)),
                      Text('KCAL',
                          style: Typo.mono(
                              7, FontWeight.w700, Palette.textLow)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
