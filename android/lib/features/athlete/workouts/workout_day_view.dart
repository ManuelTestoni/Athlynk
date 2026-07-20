import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/haptics.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/particle_burst.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/ring_gauge.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';
import '../session/active_session_view.dart';
import 'exercise_detail_view.dart';

/// One training day — port of iOS `WorkoutDayView`: exercise cards with a
/// LOCAL-only "ready" checkbox (never persisted — a pre-session checklist),
/// completion ring, confetti banner when all ticked, "AVVIA SESSIONE" CTA.
class WorkoutDayView extends StatefulWidget {
  const WorkoutDayView({
    super.key,
    required this.day,
    required this.assignmentId,
  });

  final WorkoutDayDto day;
  final int assignmentId;

  @override
  State<WorkoutDayView> createState() => _WorkoutDayViewState();
}

class _WorkoutDayViewState extends State<WorkoutDayView> {
  final Set<int> _checked = {};
  int _burst = 0;

  bool get _allDone =>
      widget.day.exercises.isNotEmpty &&
      _checked.length == widget.day.exercises.length;

  void _toggle(ExerciseDto ex) {
    setState(() {
      if (_checked.contains(ex.id)) {
        _checked.remove(ex.id);
      } else {
        _checked.add(ex.id);
        Haptics.thud();
        if (_checked.length == widget.day.exercises.length) {
          _burst++;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final progress = day.exercises.isEmpty
        ? 0.0
        : _checked.length / day.exercises.length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: Stack(
        children: [
          ScreenScroll(
            topPadding: 0,
            spacing: Space.element,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ScreenHeader(
                      eyebrow: day.dayName ?? 'Giorno ${day.dayOrder}',
                      title: day.focusArea ?? day.label,
                      titleSize: 30,
                      subtitle: day.notes,
                    ),
                  ),
                  RingGauge(
                    progress: progress,
                    size: 64,
                    stroke: 7,
                    color: Palette.magenta,
                    center: Text('${(progress * 100).round()}%',
                        style: Typo.mono(11, FontWeight.w700)),
                  ),
                ],
              ),
              if (_allDone)
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ParticleBurst(trigger: _burst),
                    VoltPanel(
                      tint: Palette.lime.withValues(alpha: 0.5),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_rounded,
                              color: Palette.lime),
                          const SizedBox(width: 10),
                          Text('SESSIONE COMPLETA',
                              style: Typo.mono(
                                      12, FontWeight.w700, Palette.lime)
                                  .copyWith(letterSpacing: 2)),
                        ],
                      ),
                    ),
                  ],
                ),
              for (final (i, ex) in day.exercises.indexed)
                RevealUp(index: i, child: _exerciseCard(ex)),
              const SizedBox(height: 70),
            ],
          ),
          Positioned(
            left: Space.screenH,
            right: Space.screenH,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: NeonButton(
              'AVVIA SESSIONE',
              color: Palette.magenta,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ActiveSessionView(
                    assignmentId: widget.assignmentId,
                    day: day,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exerciseCard(ExerciseDto ex) {
    final done = _checked.contains(ex.id);
    return VoltPanel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ExerciseDetailView(exercise: ex))),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Pressable(
            haptic: false,
            onTap: () => _toggle(ex),
            child: AnimatedContainer(
              duration: Motion.snappyDuration,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? Palette.lime : Colors.transparent,
                border: Border.all(
                    color: done ? Palette.lime : Palette.textLow, width: 2),
              ),
              child: done
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Palette.void0)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          ExerciseThumb(url: ex.coverImage),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ex.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Typo.body(15, FontWeight.w700).copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? Palette.textLow : Palette.textHi,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _chip(ex.setsReps, Palette.magenta),
                    if (ex.loadLabel != null)
                      _chip(ex.loadLabel!, Palette.cyan),
                    if (ex.recoverySeconds != null)
                      _chip('${ex.recoverySeconds}s rec', Palette.textMid),
                    if (ex.rpe != null) _chip('RPE ${ex.rpe}', Palette.amber),
                    if (ex.rir != null) _chip('RIR ${ex.rir}', Palette.amber),
                    if ((ex.tempo ?? '').isNotEmpty)
                      _chip('Tempo ${ex.tempo}', Palette.violet),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: Palette.textLow),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: Typo.mono(9.5, FontWeight.w600, color)),
    );
  }
}
