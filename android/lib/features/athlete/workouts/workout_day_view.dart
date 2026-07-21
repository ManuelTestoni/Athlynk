import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/haptics.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';
import '../session/active_session_view.dart';
import 'exercise_detail_view.dart';

/// One training day — exercises shown ONE AT A TIME. Swipe or use the prev/next
/// arrows to move between them; each page shows the full prescription + media +
/// execution + coach note. A position indicator ("3 / 8") keeps the athlete
/// oriented. "AVVIA SESSIONE" opens the live logger.
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
  final PageController _controller = PageController();
  int _current = 0;

  int get _count => widget.day.exercises.length;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = _current + delta;
    if (next < 0 || next >= _count) return;
    Haptics.soft();
    _controller.animateToPage(
      next,
      duration: Motion.snappyDuration,
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.screenH, 0, Space.screenH, 0),
              child: ScreenHeader(
                eyebrow: day.dayName ?? 'Giorno ${day.dayOrder}',
                title: day.focusArea ?? day.label,
                titleSize: 26,
                subtitle: day.notes,
              ),
            ),
            const SizedBox(height: 8),
            if (_count == 0)
              const Expanded(
                child: Center(child: Text('Nessun esercizio.')),
              )
            else
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemCount: _count,
                  itemBuilder: (_, i) =>
                      ExerciseDetailBody(exercise: day.exercises[i]),
                ),
              ),
            if (_count > 0) _navBar(),
            Padding(
              padding: EdgeInsets.fromLTRB(Space.screenH, 8, Space.screenH,
                  MediaQuery.of(context).padding.bottom + 12),
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
      ),
    );
  }

  Widget _navBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.screenH),
      child: Row(
        children: [
          _arrow(Icons.chevron_left_rounded, _current > 0, () => _go(-1)),
          const Spacer(),
          Text('${_current + 1} / $_count',
              style: Typo.mono(14, FontWeight.w800)),
          const Spacer(),
          _arrow(Icons.chevron_right_rounded, _current < _count - 1,
              () => _go(1)),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Palette.magenta : Palette.void2,
        ),
        child: Icon(icon,
            size: 22, color: enabled ? Palette.void0 : Palette.textLow),
      ),
    );
  }
}
