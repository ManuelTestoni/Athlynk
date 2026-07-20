import 'package:flutter/material.dart';

import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';
import 'workout_day_view.dart';

/// One plan — port of iOS `WorkoutPlanDetailView`: header, progress, metric
/// pills, description, day list.
class WorkoutPlanDetailView extends StatelessWidget {
  const WorkoutPlanDetailView({super.key, required this.plan});

  final WorkoutPlanDto plan;

  @override
  Widget build(BuildContext context) {
    final start = Formatters.parseDate(plan.startDate);
    final exerciseCount =
        plan.days.fold<int>(0, (s, d) => s + d.exercises.length);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        children: [
          ScreenHeader(
            eyebrow: plan.level ?? 'Scheda attiva',
            title: plan.title,
            titleSize: 32,
            subtitle: plan.goal,
          ),
          Row(
            children: [
              _metric('${plan.days.length}', 'giorni'),
              _metric('${plan.frequencyPerWeek ?? "—"}', '×sett'),
              _metric('${plan.durationWeeks ?? "—"}', 'settimane'),
              _metric('$exerciseCount', 'esercizi'),
            ],
          ),
          if ((plan.description ?? '').isNotEmpty)
            VoltPanel(
              child: Text(plan.description!,
                  style: Typo.body(14, FontWeight.w400, Palette.textMid)),
            ),
          if (start != null)
            Text('Iniziata il ${Formatters.longDate(start)}',
                style: Typo.mono(11, FontWeight.w600, Palette.textLow)),
          const SectionHeader(title: 'Giorni', eyebrow: 'Programma'),
          for (final (i, day) in plan.days.indexed)
            RevealUp(
              index: i,
              child: VoltPanel(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WorkoutDayView(
                        day: day, assignmentId: plan.assignmentId),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Palette.magenta.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text('${day.dayOrder}',
                          style: Typo.poster(20, color: Palette.magenta)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(day.label,
                              style: Typo.body(15.5, FontWeight.w700)),
                          Text(
                            day.focusArea ??
                                '${day.exercises.length} esercizi',
                            style: Typo.body(
                                12.5, FontWeight.w400, Palette.textMid),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 20, color: Palette.textLow),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metric(String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: voltPanel(),
        child: Column(
          children: [
            Text(value, style: Typo.poster(20)),
            const SizedBox(height: 2),
            Text(label.toUpperCase(),
                style: Typo.mono(8, FontWeight.w700, Palette.textLow)
                    .copyWith(letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}
