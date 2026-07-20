import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/push/push_bridge.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import 'workout_history_view.dart';
import 'workout_plan_detail_view.dart';

/// Train tab root — port of iOS `WorkoutsView`: assigned-plan summary cards
/// (elapsed-% progress, pills, coach chip) + history link. Keeps stale data
/// on refetch failure.
class WorkoutsView extends ConsumerStatefulWidget {
  const WorkoutsView({super.key});

  @override
  ConsumerState<WorkoutsView> createState() => _WorkoutsViewState();
}

class _WorkoutsViewState extends ConsumerState<WorkoutsView> {
  List<WorkoutPlanDto>? _plans;
  bool _error = false;
  StreamSubscription<String>? _remote;

  @override
  void initState() {
    super.initState();
    _load();
    _remote = ref
        .read(pushBridgeProvider)
        .onTypes({RemoteChangeType.workoutAssigned}).listen((_) => _load());
  }

  @override
  void dispose() {
    _remote?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final plans = await ref.read(apiClientProvider).workouts();
      if (mounted) {
        setState(() {
          _plans = plans;
          _error = false;
        });
      }
    } catch (_) {
      // Keep stale data; only surface the error when we have nothing.
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
        const ScreenHeader(
            eyebrow: 'Le tue schede', title: 'Allenamento'),
        if (plans == null && !_error)
          const ListCardsSkeleton(count: 2, height: 190)
        else if (_error)
          EmptyPanel.network(onCta: () {
            setState(() => _error = false);
            _load();
          })
        else if (plans!.isEmpty)
          const EmptyPanel(
            icon: Icons.fitness_center_outlined,
            message:
                'Nessuna scheda attiva. Il tuo coach la sta preparando.',
          )
        else
          for (final (i, plan) in plans.indexed)
            RevealUp(index: i, child: _planCard(plan)),
        NavListRow(
          title: 'Storico allenamenti',
          subtitle: 'Le tue sessioni passate',
          icon: Icons.history_rounded,
          accent: Palette.magenta,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const WorkoutHistoryView())),
        ),
      ],
    );
  }

  Widget _planCard(WorkoutPlanDto plan) {
    final start = Formatters.parseDate(plan.startDate);
    double progress = 0;
    if (start != null && (plan.durationWeeks ?? 0) > 0) {
      final total = plan.durationWeeks! * 7;
      final elapsed = DateTime.now().difference(start).inDays;
      progress = (elapsed / total).clamp(0.0, 1.0);
    }
    return VoltPanel(
      tint: Palette.magenta.withValues(alpha: 0.4),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => WorkoutPlanDetailView(plan: plan))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StatusBadge('Attivo', color: Palette.lime),
              const Spacer(),
              if (start != null)
                Text(Formatters.mediumDate(start),
                    style: Typo.mono(10, FontWeight.w600, Palette.textLow)),
            ],
          ),
          const SizedBox(height: 10),
          Text(plan.title, style: Typo.display(22)),
          if ((plan.goal ?? '').isNotEmpty)
            Text(plan.goal!,
                style: Typo.body(13, FontWeight.w400, Palette.textMid)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Palette.void2,
              color: Palette.magenta,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill('${plan.days.length} giorni'),
              if (plan.frequencyPerWeek != null)
                _pill('${plan.frequencyPerWeek}× a settimana'),
              if (plan.durationWeeks != null)
                _pill('${plan.durationWeeks} settimane'),
            ],
          ),
          if (plan.coach != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 14, color: Palette.textLow),
                const SizedBox(width: 6),
                Text(plan.coach!.fullName,
                    style: Typo.body(12.5, FontWeight.w600, Palette.textMid)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Palette.void2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: Typo.mono(10, FontWeight.w600, Palette.textMid)),
    );
  }
}
