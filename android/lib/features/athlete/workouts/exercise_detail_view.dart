import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/exercise_trend_card.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';

/// Full exercise prescription — port of iOS `ExerciseDetailView`: media hero,
/// stat grid, description, numbered instructions, equipment, coach note,
/// self-loading trend chart.
class ExerciseDetailView extends StatelessWidget {
  const ExerciseDetailView({super.key, required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ExerciseDetailBody(exercise: exercise),
    );
  }
}

/// Reusable exercise content (no Scaffold) — used standalone and embedded in
/// the day pager, one exercise per page.
class ExerciseDetailBody extends ConsumerWidget {
  const ExerciseDetailBody({super.key, required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ex = exercise;
    return ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        children: [
          ScreenHeader(
            eyebrow: ex.targetMuscleGroup ?? 'Esercizio',
            title: ex.name,
            titleSize: 28,
          ),
          ExerciseMediaHero(demoGif: ex.demoGif, coverImage: ex.coverImage),
          if ((ex.videoUrl ?? '').isNotEmpty)
            NavListRow(
              title: 'Guarda il video',
              icon: Icons.play_circle_outline_rounded,
              accent: Palette.magenta,
              onTap: () => launchUrl(Uri.parse(ex.videoUrl!),
                  mode: LaunchMode.externalApplication),
            ),
          _statGrid(ex),
          if ((ex.techniqueNotes ?? '').isNotEmpty)
            VoltPanel(
              tint: Palette.amber.withValues(alpha: 0.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Nota del coach'),
                  const SizedBox(height: 6),
                  Text(ex.techniqueNotes!,
                      style: Typo.body(14, FontWeight.w500)),
                ],
              ),
            ),
          // Single execution text (instruction_steps only — description is
          // deduplicated away). Collapsed to the first step by default.
          if (ex.executionSteps.isNotEmpty)
            ExecutionStepsPanel(steps: ex.executionSteps),
          if (ex.equipment.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final eq in ex.equipment)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Palette.void1,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Palette.line),
                    ),
                    child: Text(eq,
                        style: Typo.mono(
                            10, FontWeight.w600, Palette.textMid)),
                  ),
              ],
            ),
          ExerciseTrendCard(
            loader: () =>
                ref.read(apiClientProvider).exerciseTrend(ex.id),
          ),
        ],
    );
  }

  Widget _statGrid(ExerciseDto ex) {
    final stats = <(String, String)>[
      ('Serie', ex.setCount?.toString() ?? '—'),
      ('Ripetizioni', ex.repRange ?? ex.repCount?.toString() ?? '—'),
      ('Carico', ex.loadLabel ?? '—'),
      ('Recupero',
          ex.recoverySeconds == null ? '—' : '${ex.recoverySeconds}s'),
      if (ex.rpe != null) ('RPE', '${ex.rpe}'),
      if (ex.rir != null) ('RIR', '${ex.rir}'),
      if ((ex.tempo ?? '').isNotEmpty) ('Tempo', ex.tempo!),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [
        for (final (label, value) in stats)
          Container(
            decoration: voltPanel(radius: 14),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  child: Text(value, style: Typo.poster(19)),
                ),
                const SizedBox(height: 2),
                Text(label.toUpperCase(),
                    style: Typo.mono(7.5, FontWeight.w700, Palette.textLow)
                        .copyWith(letterSpacing: 1)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Execution steps shown one-line-collapsed with a "Vedi esecuzione" toggle.
class ExecutionStepsPanel extends StatefulWidget {
  const ExecutionStepsPanel({super.key, required this.steps});

  final List<String> steps;

  @override
  State<ExecutionStepsPanel> createState() => _ExecutionStepsPanelState();
}

class _ExecutionStepsPanelState extends State<ExecutionStepsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    final visible = _expanded ? steps : steps.take(1).toList();
    return VoltPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Esecuzione'),
          const SizedBox(height: 10),
          for (final (i, step) in visible.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Palette.magenta.withValues(alpha: 0.1),
                    ),
                    alignment: Alignment.center,
                    child: Text('${i + 1}',
                        style:
                            Typo.mono(10, FontWeight.w700, Palette.magenta)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(step,
                        maxLines: _expanded ? null : 1,
                        overflow: _expanded ? null : TextOverflow.ellipsis,
                        style: Typo.body(13.5, FontWeight.w400)),
                  ),
                ],
              ),
            ),
          if (steps.length > 1)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_expanded ? 'Nascondi' : 'Vedi esecuzione',
                        style:
                            Typo.mono(11, FontWeight.w700, Palette.magenta)),
                    const SizedBox(width: 4),
                    Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: Palette.magenta),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
