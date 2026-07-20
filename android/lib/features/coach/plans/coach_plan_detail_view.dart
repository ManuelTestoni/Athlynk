import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/confirm_dialog.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';
import 'coach_progression_grid_view.dart';
import 'coach_workout_wizard_view.dart';

/// Read-only plan detail with edit/duplicate/delete — port of iOS
/// `CoachWorkoutDetailView`/`CoachNutritionDetailView`.
class CoachPlanDetailView extends ConsumerStatefulWidget {
  const CoachPlanDetailView({
    super.key,
    required this.planId,
    required this.workout,
  });

  final int planId;
  final bool workout;

  @override
  ConsumerState<CoachPlanDetailView> createState() =>
      _CoachPlanDetailViewState();
}

class _CoachPlanDetailViewState extends ConsumerState<CoachPlanDetailView> {
  WorkoutPlanDto? _workoutPlan;
  Map<String, dynamic>? _nutritionPlan;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      if (widget.workout) {
        final p = await api.coachWorkoutDetail(widget.planId);
        if (mounted) setState(() => _workoutPlan = p);
      } else {
        final p = await api.coachNutritionDetail(widget.planId);
        if (mounted) setState(() => _nutritionPlan = p);
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _menu(String action) async {
    final api = ref.read(apiClientProvider);
    try {
      switch (action) {
        case 'edit':
          await showAppSheet<void>(
            context,
            builder: (_) => CoachWorkoutWizardView(
                workout: widget.workout, planId: widget.planId),
          );
          await _load();
        case 'progression':
          final plan = _workoutPlan;
          if (plan != null && plan.days.isNotEmpty) {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => CoachProgressionGridView(
                  planId: widget.planId, days: plan.days),
            ));
          }
        case 'duplicate':
          if (widget.workout) {
            await api.duplicateWorkoutPlan(widget.planId);
          } else {
            await api.duplicateNutritionPlan(widget.planId);
          }
          if (mounted) {
            StatusFlash.show(context,
                success: true, message: 'Piano duplicato');
          }
        case 'delete':
          final ok = await ConfirmCenter.confirm(
            context,
            const ConfirmOptions(
              title: 'Eliminare questo piano?',
              subtitle: 'Le assegnazioni attive verranno rimosse.',
              icon: Icons.delete_forever_rounded,
              variant: ConfirmVariant.danger,
              confirmLabel: 'Elimina',
            ),
          );
          if (ok) {
            if (widget.workout) {
              await api.deleteWorkoutPlan(widget.planId);
            } else {
              await api.deleteNutritionPlan(widget.planId);
            }
            if (mounted) Navigator.of(context).pop();
          }
      }
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Operazione non riuscita');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Palette.textHi),
            color: Palette.void0,
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'edit',
                  child: Text('Modifica',
                      style: Typo.body(14, FontWeight.w500))),
              if (widget.workout && _workoutPlan != null)
                PopupMenuItem(
                    value: 'progression',
                    child: Text('Griglia progressioni',
                        style: Typo.body(14, FontWeight.w500))),
              PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplica',
                      style: Typo.body(14, FontWeight.w500))),
              PopupMenuItem(
                  value: 'delete',
                  child: Text('Elimina',
                      style: Typo.body(
                          14, FontWeight.w500, Palette.crimson))),
            ],
          ),
        ],
      ),
      body: _error
          ? Padding(
              padding: const EdgeInsets.all(Space.screenH),
              child: EmptyPanel.network(onCta: () {
                setState(() => _error = false);
                _load();
              }),
            )
          : widget.workout
              ? _workoutBody()
              : _nutritionBody(),
    );
  }

  Widget _workoutBody() {
    final p = _workoutPlan;
    if (p == null) {
      return const Padding(
          padding: EdgeInsets.all(Space.screenH), child: FormSkeleton());
    }
    return ScreenScroll(
      topPadding: 0,
      spacing: Space.element,
      children: [
        ScreenHeader(
            eyebrow: p.goal ?? 'Scheda',
            title: p.title,
            titleSize: 30,
            subtitle: p.description),
        for (final day in p.days)
          VoltPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(day.label, style: Typo.display(17)),
                if (day.focusArea != null)
                  Text(day.focusArea!,
                      style: Typo.body(
                          12.5, FontWeight.w400, Palette.textMid)),
                const SizedBox(height: 10),
                for (final ex in day.exercises)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(ex.name,
                                style: Typo.body(14, FontWeight.w600))),
                        Text(
                          '${ex.setsReps}${ex.loadLabel == null ? '' : ' · ${ex.loadLabel}'}',
                          style: Typo.mono(
                              11, FontWeight.w600, Palette.textMid),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _nutritionBody() {
    final p = _nutritionPlan;
    if (p == null) {
      return const Padding(
          padding: EdgeInsets.all(Space.screenH), child: FormSkeleton());
    }
    final plan = (p['plan'] ?? p) as Map<String, dynamic>;
    final days = (plan['days'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    return ScreenScroll(
      topPadding: 0,
      spacing: Space.element,
      children: [
        ScreenHeader(
          eyebrow:
              '${plan['plan_mode'] ?? 'FOOD'} · ${plan['plan_kind'] ?? 'DAILY'}',
          title: (plan['title'] as String?) ?? 'Piano',
          titleSize: 30,
        ),
        for (final day in days)
          VoltPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((day['day_of_week'] as String?) ?? 'Giorno',
                    style: Typo.display(16)),
                const SizedBox(height: 6),
                if (day['target_kcal'] != null)
                  Text(
                    '${day['target_kcal']} kcal · P ${day['target_protein_g'] ?? '—'} · C ${day['target_carb_g'] ?? '—'} · F ${day['target_fat_g'] ?? '—'}',
                    style:
                        Typo.mono(11, FontWeight.w600, Palette.textMid),
                  ),
                for (final meal in (day['meals'] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    const <Map<String, dynamic>>[])
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.restaurant_rounded,
                            size: 13, color: Palette.lime),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text((meal['name'] as String?) ?? 'Pasto',
                              style: Typo.body(13.5, FontWeight.w600)),
                        ),
                        Text(
                            '${((meal['items'] as List?) ?? const []).length} alimenti',
                            style: Typo.mono(
                                10, FontWeight.w600, Palette.textLow)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
