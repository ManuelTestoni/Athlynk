import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import 'coach_folders_view.dart';
import 'coach_plan_detail_view.dart';
import 'coach_plan_import_view.dart';
import 'coach_workout_wizard_view.dart';

/// Plan library — port of iOS `CoachWorkoutsView`/`CoachNutritionView`
/// (`CoachPlansView.swift`): search, folders, create (builder or AI import),
/// plan rows + active assignments.
class CoachPlansView extends ConsumerStatefulWidget {
  const CoachPlansView({super.key, required this.workout});

  /// true = Allenamento tab, false = Nutrizione tab.
  final bool workout;

  @override
  ConsumerState<CoachPlansView> createState() => _CoachPlansViewState();
}

class _CoachPlansViewState extends ConsumerState<CoachPlansView> {
  final _query = TextEditingController();
  CoachWorkoutsResponse? _res;
  bool _error = false;

  Color get _accent => widget.workout ? Palette.cyan : Palette.lime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final res = widget.workout
          ? await api.coachWorkouts(q: _query.text.trim())
          : await api.coachNutrition(q: _query.text.trim());
      if (mounted) {
        setState(() {
          _res = res;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted && _res == null) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ScreenScroll(
        onRefresh: _load,
        spacing: Space.element,
        children: [
          ScreenHeader(
            eyebrow: widget.workout ? 'Schede allenamento' : 'Piani alimentari',
            title: widget.workout ? 'Allenamento' : 'Nutrizione',
          ),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: voltPanel(radius: Radii.field),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded,
                          size: 18, color: Palette.textLow),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _query,
                          style: Typo.body(15, FontWeight.w500),
                          decoration: InputDecoration(
                            hintText: 'Cerca…',
                            hintStyle: Typo.body(
                                15, FontWeight.w400, Palette.textLow),
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => _load(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Cartelle',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CoachFoldersView(
                        domain:
                            widget.workout ? 'allenamenti' : 'nutrizione'),
                  ),
                ),
                icon: const Icon(Icons.folder_open_rounded, size: 20),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: QuickActionTile(
                  icon: Icons.add_rounded,
                  label: 'Nuovo',
                  accent: _accent,
                  onTap: () => showAppSheet<void>(
                    context,
                    builder: (_) =>
                        CoachWorkoutWizardView(workout: widget.workout),
                  ).then((_) => _load()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuickActionTile(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Import AI',
                  accent: Palette.amber,
                  onTap: () => showAppSheet<void>(
                    context,
                    builder: (_) =>
                        CoachPlanImportView(workout: widget.workout),
                  ).then((_) => _load()),
                ),
              ),
            ],
          ),
          if (res == null && !_error)
            const ListCardsSkeleton(count: 3, height: 120)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else ...[
            if (res!.assignments.isNotEmpty) ...[
              const Eyebrow('Assegnazioni attive'),
              for (final a in res.assignments.take(6))
                VoltPanel(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.planTitle,
                                style: Typo.body(14, FontWeight.w700)),
                            if (a.client != null)
                              Text(a.client!.displayName,
                                  style: Typo.body(12, FontWeight.w400,
                                      Palette.textMid)),
                          ],
                        ),
                      ),
                      StatusBadge(a.status ?? 'Attiva', color: _accent),
                    ],
                  ),
                ),
            ],
            const Eyebrow('Libreria'),
            if (res.plans.isEmpty)
              EmptyPanel(
                icon: widget.workout
                    ? Icons.fitness_center_outlined
                    : Icons.restaurant_outlined,
                message:
                    'Nessun piano ancora: creane uno con "Nuovo" o importalo con l\'AI.',
              )
            else
              for (final p in res.plans)
                VoltPanel(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CoachPlanDetailView(
                          planId: p.id, workout: widget.workout),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(p.title,
                                  style: Typo.display(17))),
                          StatusBadge(
                            switch ((p.status ?? '').toUpperCase()) {
                              'ACTIVE' => 'Attivo',
                              'TEMPLATE' => 'Template',
                              _ => 'Bozza',
                            },
                            color: switch ((p.status ?? '').toUpperCase()) {
                              'ACTIVE' => Palette.lime,
                              'TEMPLATE' => Palette.cyan,
                              _ => Palette.textLow,
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (p.goal != null) p.goal!,
                          if (p.daysCount != null) '${p.daysCount} giorni',
                          if (p.durationWeeks != null)
                            '${p.durationWeeks} settimane',
                          if (p.planMode != null) p.planMode!,
                        ].join(' · '),
                        style: Typo.mono(
                            10, FontWeight.w600, Palette.textMid),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
