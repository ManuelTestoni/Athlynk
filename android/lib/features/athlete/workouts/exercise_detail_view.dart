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
class ExerciseDetailView extends ConsumerWidget {
  const ExerciseDetailView({super.key, required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ex = exercise;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
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
          if ((ex.description ?? '').isNotEmpty)
            VoltPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Descrizione'),
                  const SizedBox(height: 6),
                  Text(ex.description!,
                      style:
                          Typo.body(14, FontWeight.w400, Palette.textMid)),
                ],
              ),
            ),
          if ((ex.instructionSteps ?? []).isNotEmpty)
            VoltPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Esecuzione'),
                  const SizedBox(height: 10),
                  for (final (i, step) in ex.instructionSteps!.indexed)
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
                              color:
                                  Palette.magenta.withValues(alpha: 0.1),
                            ),
                            alignment: Alignment.center,
                            child: Text('${i + 1}',
                                style: Typo.mono(
                                    10, FontWeight.w700, Palette.magenta)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(step,
                                style: Typo.body(13.5, FontWeight.w400)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
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
      ),
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
