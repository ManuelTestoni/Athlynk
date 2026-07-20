import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/weekday.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';
import 'diet_day_detail_view.dart';
import 'macro_log_view.dart';
import 'meal_detail_view.dart';

/// Full-plan detail, 4-way switch on mode/kind — port of iOS
/// `NutritionPlanDetailView`.
class NutritionPlanDetailView extends StatelessWidget {
  const NutritionPlanDetailView({super.key, required this.plan});

  final NutritionPlanDto plan;

  @override
  Widget build(BuildContext context) {
    final t = plan.overviewTargets;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        children: [
          ScreenHeader(
            eyebrow:
                '${plan.isMacro ? "Macro" : "Alimenti"} · ${plan.isWeekly ? "Settimanale" : "Giornaliero"}',
            title: plan.title,
            titleSize: 30,
            subtitle: plan.nutritionGoal,
          ),
          VoltPanel(
            child: Row(
              children: [
                _col('${t.kcal}', 'kcal', Palette.amber),
                _col('${t.protein ?? "—"}g', 'prot', Palette.magenta),
                _col('${t.carb ?? "—"}g', 'carb', Palette.cyan),
                _col('${t.fat ?? "—"}g', 'grassi', Palette.lime),
              ],
            ),
          ),
          if (!plan.isMacro && plan.isWeekly)
            for (final day in plan.days) _foodDayBlock(context, day)
          else if (!plan.isMacro)
            for (final meal in plan.days.isEmpty
                ? const <MealDto>[]
                : plan.days.first.meals)
              _mealRow(context, meal)
          else if (plan.isWeekly)
            for (final day in plan.days) _macroDayRow(context, day)
          else
            NavListRow(
              title: 'Apri il diario',
              subtitle: 'Registra i tuoi pasti di oggi',
              icon: Icons.edit_note_rounded,
              accent: Palette.cyan,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      MacroLogView(assignmentId: plan.assignmentId),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _col(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: Typo.poster(20)),
          Text(label.toUpperCase(),
              style: Typo.mono(7.5, FontWeight.w700, color)
                  .copyWith(letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _foodDayBlock(BuildContext context, DietDayDto day) {
    final weekday = DietWeekday.fromCode(day.dayOfWeek);
    return VoltPanel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => DietDayDetailView(plan: plan, initialDay: day))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(weekday?.long ?? day.dayOfWeek,
                    style: Typo.display(17)),
              ),
              Text(
                '${day.meals.fold<double>(0, (s, m) => s + m.kcal).toInt()} kcal',
                style: Typo.mono(12, FontWeight.w700, Palette.amber),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            day.meals.map((m) => m.name).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Typo.body(12.5, FontWeight.w400, Palette.textMid),
          ),
        ],
      ),
    );
  }

  Widget _mealRow(BuildContext context, MealDto meal) {
    return VoltPanel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MealDetailView(meal: meal))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.restaurant_rounded, size: 17, color: Palette.lime),
          const SizedBox(width: 12),
          Expanded(
              child: Text(meal.name, style: Typo.body(15, FontWeight.w700))),
          Text('${meal.kcal.toInt()} kcal',
              style: Typo.mono(12, FontWeight.w700, Palette.amber)),
        ],
      ),
    );
  }

  Widget _macroDayRow(BuildContext context, DietDayDto day) {
    final weekday = DietWeekday.fromCode(day.dayOfWeek);
    return VoltPanel(
      onTap: () {
        final date = weekday?.dateInWeekOf(DateTime.now());
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MacroLogView(
              assignmentId: plan.assignmentId, logDate: date),
        ));
      },
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(weekday?.short ?? day.dayOfWeek,
                style: Typo.mono(11, FontWeight.w700, Palette.cyan)),
          ),
          Expanded(
            child: Text(
              'P ${day.targetProteinG ?? "—"} · C ${day.targetCarbG ?? "—"} · F ${day.targetFatG ?? "—"}',
              style: Typo.mono(11, FontWeight.w600, Palette.textMid),
            ),
          ),
          Text('${day.targetKcal ?? "—"} kcal',
              style: Typo.mono(12, FontWeight.w700, Palette.amber)),
        ],
      ),
    );
  }
}
