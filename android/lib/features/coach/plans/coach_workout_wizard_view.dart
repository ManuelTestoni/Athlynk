import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/api/coach_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/rpe_rir.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/confirm_dialog.dart';
import '../../../design/components/exercise_picker_sheet.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Plan wizard — port of iOS `CoachWorkoutWizardView`/`CoachNutritionWizardView`
/// + the native card builder (`CoachPlanBuilderView`): Dettagli → Struttura →
/// Finalizza (template / assegna / bozza), writing through the same
/// save/finalize endpoints the web app uses. Serves both domains:
/// workout (days+exercises) and nutrition (FOOD meals / MACRO targets).
class CoachWorkoutWizardView extends ConsumerStatefulWidget {
  const CoachWorkoutWizardView({
    super.key,
    required this.workout,
    this.planId,
  });

  final bool workout;
  final int? planId;

  @override
  ConsumerState<CoachWorkoutWizardView> createState() =>
      _CoachWorkoutWizardViewState();
}

class _WizardDay {
  _WizardDay(this.name);
  String name;
  String focus = '';
  final List<Map<String, dynamic>> exercises = [];
  final List<Map<String, dynamic>> meals = [];
  int? targetKcal;
  int? targetProtein;
  int? targetCarb;
  int? targetFat;
}

class _CoachWorkoutWizardViewState
    extends ConsumerState<CoachWorkoutWizardView> {
  int _step = 0;
  final _title = TextEditingController();
  final _goal = TextEditingController();
  String _kind = 'WEEKLY'; // workout: WEEKLY|PROGRAM · nutrition: DAILY|WEEKLY
  String _mode = 'FOOD'; // nutrition only: FOOD|MACRO
  int _durationWeeks = 8;
  bool _useRir = true;
  final List<_WizardDay> _days = [];
  bool _saving = false;
  int? _savedPlanId;

  Color get _accent => widget.workout ? Palette.cyan : Palette.lime;

  @override
  void initState() {
    super.initState();
    _savedPlanId = widget.planId;
    if (widget.planId != null && widget.workout) _loadExisting();
    if (_days.isEmpty) {
      _days.add(_WizardDay(widget.workout ? 'Giorno A' : 'LUNEDÌ'));
    }
  }

  Future<void> _loadExisting() async {
    try {
      final plan = await ref
          .read(apiClientProvider)
          .coachWorkoutDetail(widget.planId!);
      if (!mounted) return;
      setState(() {
        _title.text = plan.title;
        _goal.text = plan.goal ?? '';
        _durationWeeks = plan.durationWeeks ?? 8;
        _days
          ..clear()
          ..addAll(plan.days.map((d) {
            final day = _WizardDay(d.label)..focus = d.focusArea ?? '';
            for (final e in d.exercises) {
              day.exercises.add({
                'exercise_id': e.id,
                'name': e.name,
                'sets': e.setCount ?? 3,
                'reps': e.repRange ?? '${e.repCount ?? 10}',
                'load_value': e.loadValue,
                'recovery_seconds': e.recoverySeconds ?? 90,
                'rir': e.rir,
                'rpe': e.rpe,
                'tempo': e.tempo,
                'notes': e.techniqueNotes,
              });
            }
            return day;
          }));
        if (_days.isEmpty) _days.add(_WizardDay('Giorno A'));
      });
    } catch (_) {}
  }

  // ── Persistence ──

  Map<String, dynamic> _workoutBody() => {
        'title': _title.text.trim(),
        'goal': _goal.text.trim(),
        'plan_kind': _kind,
        'duration_weeks': _durationWeeks,
        'days': [
          for (final (i, d) in _days.indexed)
            {
              'day_order': i + 1,
              'day_name': d.name,
              'focus_area': d.focus,
              'exercises': [
                for (final (j, e) in d.exercises.indexed)
                  {...e, 'order_index': j},
              ],
            },
        ],
      };

  Map<String, dynamic> _nutritionBody() => {
        'title': _title.text.trim(),
        'nutrition_goal': _goal.text.trim(),
        'plan_kind': _kind,
        'plan_mode': _mode,
        'days': [
          for (final d in _days)
            {
              'day_of_week': d.name,
              if (_mode == 'MACRO') ...{
                'target_kcal': d.targetKcal,
                'target_protein_g': d.targetProtein,
                'target_carb_g': d.targetCarb,
                'target_fat_g': d.targetFat,
              },
              if (_mode == 'FOOD') 'meals': d.meals,
            },
        ],
      };

  Future<bool> _saveDraft() async {
    if (_title.text.trim().isEmpty) {
      StatusFlash.show(context,
          success: false, message: 'Dai un titolo al piano');
      return false;
    }
    final api = ref.read(apiClientProvider);
    try {
      if (widget.workout) {
        final res = await api.saveWorkoutPlan(_workoutBody(),
            planId: _savedPlanId);
        _savedPlanId = (res['id'] as num?)?.toInt() ?? _savedPlanId;
      } else {
        if (_savedPlanId == null) {
          final res = await api.createNutritionPlan(_nutritionBody());
          _savedPlanId = (res['id'] as num?)?.toInt();
        } else {
          await api.updateNutritionPlan(_savedPlanId!, _nutritionBody());
        }
      }
      return true;
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Salvataggio non riuscito');
      }
      return false;
    }
  }

  Future<void> _finalize(String modeAction) async {
    if (_saving) return;
    setState(() => _saving = true);
    final api = ref.read(apiClientProvider);
    try {
      if (!await _saveDraft()) return;
      List<int> clientIds = const [];
      if (modeAction == 'assign') {
        final picked = await _pickClients();
        if (picked == null) return;
        clientIds = picked;
      }
      if (widget.workout) {
        await api.finalizeWorkoutPlan(_savedPlanId!, {
          'mode': modeAction,
          if (clientIds.isNotEmpty) 'client_ids': clientIds,
        });
      } else if (modeAction == 'assign') {
        await api.assignNutritionPlan(
            _savedPlanId!, {'client_ids': clientIds});
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      StatusFlash.show(context,
          success: true,
          message: switch (modeAction) {
            'assign' => 'Piano assegnato',
            'template' => 'Salvato come template',
            _ => 'Bozza salvata',
          });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<List<int>?> _pickClients() async {
    final clients =
        await ref.read(apiClientProvider).coachClients(status: 'ACTIVE', limit: 100);
    if (!mounted) return null;
    final selected = <int>{};
    final result = await showAppSheet<List<int>>(
      context,
      heightFactor: 0.8,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Scaffold(
          backgroundColor: Palette.void0,
          appBar: AppBar(
              title: Text('Assegna a…', style: Typo.display(18))),
          body: ListView(
            padding: const EdgeInsets.all(Space.screenH),
            children: [
              for (final c in clients.clients)
                CheckboxListTile(
                  value: selected.contains(c.id),
                  activeColor: _accent,
                  contentPadding: EdgeInsets.zero,
                  secondary: AvatarView(
                      url: c.profileImageUrl,
                      name: c.displayName,
                      size: 38),
                  title: Text(c.displayName,
                      style: Typo.body(14.5, FontWeight.w600)),
                  subtitle: c.activeWorkout == null
                      ? null
                      : Text('Attiva: ${c.activeWorkout}',
                          style: Typo.body(
                              11, FontWeight.w400, Palette.amber)),
                  onChanged: (v) => setSheetState(() {
                    if (v == true) {
                      selected.add(c.id);
                    } else {
                      selected.remove(c.id);
                    }
                  }),
                ),
              const SizedBox(height: 14),
              NeonButton('Conferma', color: _accent, onTap: () {
                Navigator.of(sheetContext, rootNavigator: true)
                    .pop(selected.toList());
              }),
            ],
          ),
        ),
      ),
    );
    if (result == null || result.isEmpty) return null;
    // Overwrite-active confirmation (parity with iOS).
    final anyActive = clients.clients
        .where((c) => result.contains(c.id))
        .any((c) => c.activeWorkout != null);
    if (anyActive && widget.workout && mounted) {
      final ok = await ConfirmCenter.confirm(
        context,
        const ConfirmOptions(
          title: 'Sostituire la scheda attiva?',
          subtitle:
              'Alcuni atleti hanno già una scheda attiva: verrà archiviata.',
          icon: Icons.swap_horiz_rounded,
          variant: ConfirmVariant.danger,
          confirmLabel: 'Sostituisci',
        ),
      );
      if (!ok) return null;
    }
    return result;
  }

  // ── UI ──

  static const _weekdays = [
    'LUNEDÌ', 'MARTEDÌ', 'MERCOLEDÌ', 'GIOVEDÌ', 'VENERDÌ', 'SABATO', 'DOMENICA',
  ];

  @override
  Widget build(BuildContext context) {
    final steps = ['Dettagli', 'Struttura', 'Finalizza'];
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
        title: Text(
            widget.workout
                ? (widget.planId == null ? 'Nuova scheda' : 'Modifica scheda')
                : (widget.planId == null ? 'Nuovo piano' : 'Modifica piano'),
            style: Typo.display(18)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.screenH),
            child: Row(
              children: [
                for (final (i, label) in steps.indexed)
                  Expanded(
                    child: Column(
                      children: [
                        Text(label,
                            style: Typo.mono(
                                9,
                                FontWeight.w700,
                                i <= _step ? _accent : Palette.textLow)),
                        const SizedBox(height: 5),
                        Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i <= _step ? _accent : Palette.void2,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (_step) {
              0 => _detailsStep(),
              1 => _structureStep(),
              _ => _finalizeStep(),
            },
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.screenH, 6, Space.screenH, 12),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: NeonButton('Indietro',
                          filled: false,
                          color: Palette.textMid,
                          onTap: () => setState(() => _step--)),
                    ),
                  if (_step > 0) const SizedBox(width: 10),
                  if (_step < 2)
                    Expanded(
                      flex: 2,
                      child: NeonButton('Avanti', color: _accent, onTap: () {
                        if (_step == 0 && _title.text.trim().isEmpty) {
                          StatusFlash.show(context,
                              success: false,
                              message: 'Dai un titolo al piano');
                          return;
                        }
                        Haptics.tap();
                        setState(() => _step++);
                      }),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsStep() {
    return ListView(
      padding: const EdgeInsets.all(Space.screenH),
      children: [
        TextField(
            controller: _title,
            style: Typo.body(16, FontWeight.w700),
            decoration: const InputDecoration(labelText: 'Titolo *')),
        const SizedBox(height: 14),
        TextField(
            controller: _goal,
            style: Typo.body(14.5, FontWeight.w500),
            decoration: InputDecoration(
                labelText: widget.workout ? 'Obiettivo' : 'Obiettivo nutrizionale')),
        const SizedBox(height: 20),
        Eyebrow(widget.workout ? 'Tipo di scheda' : 'Struttura'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final (v, l) in widget.workout
                ? const [('WEEKLY', 'Scheda settimanale'), ('PROGRAM', 'Programmazione')]
                : const [('DAILY', 'Giornaliero'), ('WEEKLY', 'Settimanale')])
              ChoiceChip(
                label: Text(l, style: Typo.body(13, FontWeight.w600)),
                selected: _kind == v,
                selectedColor: _accent.withValues(alpha: 0.2),
                onSelected: (_) => setState(() => _kind = v),
              ),
          ],
        ),
        if (!widget.workout) ...[
          const SizedBox(height: 16),
          const Eyebrow('Modalità'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (v, l) in const [
                ('FOOD', 'Alimenti'),
                ('MACRO', 'Macronutrienti')
              ])
                ChoiceChip(
                  label: Text(l, style: Typo.body(13, FontWeight.w600)),
                  selected: _mode == v,
                  selectedColor: _accent.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => _mode = v),
                ),
            ],
          ),
        ],
        if (widget.workout) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Durata: $_durationWeeks settimane',
                    style: Typo.body(14, FontWeight.w600)),
              ),
              Expanded(
                child: Slider(
                  value: _durationWeeks.toDouble(),
                  min: 1,
                  max: 24,
                  divisions: 23,
                  activeColor: _accent,
                  onChanged: (v) =>
                      setState(() => _durationWeeks = v.round()),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Usa RIR (spegni per RPE)',
                style: Typo.body(14, FontWeight.w600)),
            value: _useRir,
            onChanged: (v) async {
              // App-wide RIR↔RPE unification prompt (RPE ≈ 10 − RIR).
              final ok = await ConfirmCenter.confirm(
                context,
                ConfirmOptions(
                  title: v ? 'Convertire tutto in RIR?' : 'Convertire tutto in RPE?',
                  subtitle: 'I valori esistenti verranno convertiti (RPE ≈ 10 − RIR).',
                  icon: Icons.swap_vert_rounded,
                  confirmLabel: 'Converti',
                ),
              );
              if (!ok) return;
              setState(() {
                _useRir = v;
                for (final d in _days) {
                  for (final e in d.exercises) {
                    if (v && e['rpe'] != null) {
                      e['rir'] = rirFromRpe((e['rpe'] as num).toDouble()).round();
                      e['rpe'] = null;
                    } else if (!v && e['rir'] != null) {
                      e['rpe'] = rpeFromRir((e['rir'] as num).toDouble()).round();
                      e['rir'] = null;
                    }
                  }
                }
              });
            },
          ),
        ],
      ],
    );
  }

  Widget _structureStep() {
    return ListView(
      padding: const EdgeInsets.all(Space.screenH),
      children: [
        for (final (i, day) in _days.indexed) _dayCard(i, day),
        const SizedBox(height: 8),
        NeonButton(
          widget.workout ? 'Aggiungi giorno' : 'Aggiungi giornata',
          filled: false,
          color: _accent,
          icon: Icons.add_rounded,
          onTap: () => setState(() {
            _days.add(_WizardDay(widget.workout
                ? 'Giorno ${String.fromCharCode(65 + _days.length)}'
                : _weekdays[_days.length % 7]));
          }),
        ),
      ],
    );
  }

  Widget _dayCard(int index, _WizardDay day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: voltPanel(tint: _accent.withValues(alpha: 0.3)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: day.name,
                  style: Typo.display(16),
                  decoration: const InputDecoration(
                      isDense: true, border: InputBorder.none),
                  onChanged: (v) => day.name = v,
                ),
              ),
              if (_days.length > 1)
                Pressable(
                  onTap: () => setState(() => _days.removeAt(index)),
                  child: const Icon(Icons.remove_circle_outline_rounded,
                      size: 19, color: Palette.crimson),
                ),
            ],
          ),
          if (widget.workout) ...[
            TextFormField(
              initialValue: day.focus,
              style: Typo.body(13, FontWeight.w500, Palette.textMid),
              decoration: const InputDecoration(
                  hintText: 'Focus (es. Push)', isDense: true),
              onChanged: (v) => day.focus = v,
            ),
            const SizedBox(height: 8),
            for (final (j, e) in day.exercises.indexed)
              _exerciseRow(day, j, e),
            TextButton.icon(
              onPressed: () => _addExercise(day),
              icon: Icon(Icons.add_rounded, size: 17, color: _accent),
              label: Text('Esercizio',
                  style: Typo.body(13.5, FontWeight.w700, _accent)),
            ),
          ] else if (_mode == 'MACRO')
            _macroTargets(day)
          else
            _mealsEditor(day),
        ],
      ),
    );
  }

  Widget _exerciseRow(_WizardDay day, int index, Map<String, dynamic> e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Palette.void0,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text((e['name'] as String?) ?? 'Esercizio',
                    style: Typo.body(14, FontWeight.w700)),
              ),
              Pressable(
                onTap: () =>
                    setState(() => day.exercises.removeAt(index)),
                child: const Icon(Icons.close_rounded,
                    size: 16, color: Palette.textLow),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _numField('Serie', e, 'sets'),
              _textFieldSmall('Reps', e, 'reps'),
              _numField('Rec (s)', e, 'recovery_seconds'),
              _numField(_useRir ? 'RIR' : 'RPE', e, _useRir ? 'rir' : 'rpe'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numField(String label, Map<String, dynamic> e, String key) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: TextFormField(
          initialValue: e[key]?.toString() ?? '',
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: Typo.mono(12.5, FontWeight.w700),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            labelStyle: Typo.mono(9, FontWeight.w600, Palette.textLow),
          ),
          onChanged: (v) => e[key] = int.tryParse(v),
        ),
      ),
    );
  }

  Widget _textFieldSmall(String label, Map<String, dynamic> e, String key) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: TextFormField(
          initialValue: e[key]?.toString() ?? '',
          textAlign: TextAlign.center,
          style: Typo.mono(12.5, FontWeight.w700),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            labelStyle: Typo.mono(9, FontWeight.w600, Palette.textLow),
          ),
          onChanged: (v) => e[key] = v,
        ),
      ),
    );
  }

  void _addExercise(_WizardDay day) {
    showAppSheet<void>(
      context,
      builder: (_) => ExercisePickerSheet(
        search: ({q = '', muscleGroup = '', similarTo, includeGroups = false}) =>
            ref.read(apiClientProvider).searchExercises(
                q: q,
                muscleGroup: muscleGroup,
                similarTo: similarTo,
                includeGroups: includeGroups),
        onPick: (picked) {
          Navigator.of(context, rootNavigator: true).pop();
          setState(() {
            day.exercises.add({
              'exercise_id': picked.id,
              'name': picked.name,
              'sets': 3,
              'reps': '10',
              'recovery_seconds': 90,
            });
          });
          Haptics.thud();
        },
      ),
    );
  }

  Widget _macroTargets(_WizardDay day) {
    Widget field(String label, int? value, void Function(int?) set) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextFormField(
            initialValue: value?.toString() ?? '',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: Typo.mono(13, FontWeight.w700),
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              labelStyle: Typo.mono(9, FontWeight.w600, Palette.textLow),
            ),
            onChanged: (v) => set(int.tryParse(v)),
          ),
        ),
      );
    }

    return Row(
      children: [
        field('kcal', day.targetKcal, (v) => day.targetKcal = v),
        field('P (g)', day.targetProtein, (v) => day.targetProtein = v),
        field('C (g)', day.targetCarb, (v) => day.targetCarb = v),
        field('F (g)', day.targetFat, (v) => day.targetFat = v),
      ],
    );
  }

  Widget _mealsEditor(_WizardDay day) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (mi, meal) in day.meals.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Palette.void0,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Palette.line),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: (meal['name'] as String?) ?? '',
                        style: Typo.body(14, FontWeight.w700),
                        decoration: const InputDecoration(
                            hintText: 'Pasto (es. Pranzo)',
                            isDense: true,
                            border: InputBorder.none),
                        onChanged: (v) => meal['name'] = v,
                      ),
                    ),
                    Pressable(
                      onTap: () => setState(() => day.meals.removeAt(mi)),
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: Palette.textLow),
                    ),
                  ],
                ),
                for (final (fi, item) in ((meal['items'] as List?) ?? [])
                    .cast<Map<String, dynamic>>()
                    .indexed)
                  Row(
                    children: [
                      Expanded(
                        child: Text((item['name'] as String?) ?? '',
                            style: Typo.body(13, FontWeight.w500)),
                      ),
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          initialValue:
                              item['quantity_g']?.toString() ?? '100',
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.end,
                          style: Typo.mono(12, FontWeight.w700),
                          decoration: const InputDecoration(
                              suffixText: 'g', isDense: true),
                          onChanged: (v) =>
                              item['quantity_g'] = double.tryParse(v) ?? 100,
                        ),
                      ),
                      Pressable(
                        onTap: () => setState(
                            () => (meal['items'] as List).removeAt(fi)),
                        child: const Icon(Icons.close_rounded,
                            size: 14, color: Palette.textLow),
                      ),
                    ],
                  ),
                TextButton.icon(
                  onPressed: () => _addFood(meal),
                  icon: const Icon(Icons.add_rounded,
                      size: 15, color: Palette.lime),
                  label: Text('Alimento',
                      style:
                          Typo.body(12.5, FontWeight.w700, Palette.lime)),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: () => setState(() =>
              day.meals.add({'name': '', 'items': <Map<String, dynamic>>[]})),
          icon: const Icon(Icons.add_rounded, size: 17, color: Palette.lime),
          label: Text('Pasto',
              style: Typo.body(13.5, FontWeight.w700, Palette.lime)),
        ),
      ],
    );
  }

  void _addFood(Map<String, dynamic> meal) {
    final controller = TextEditingController();
    showAppSheet<void>(
      context,
      heightFactor: 0.8,
      builder: (sheetContext) => _FoodPickerSheet(
        onPick: (food) {
          setState(() {
            (meal['items'] as List).add({
              'food_id': food.id,
              'name': food.name,
              'quantity_g': 100.0,
            });
          });
          Navigator.of(sheetContext, rootNavigator: true).pop();
        },
      ),
    ).then((_) => controller.dispose());
  }

  Widget _finalizeStep() {
    return ListView(
      padding: const EdgeInsets.all(Space.screenH),
      children: [
        VoltPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Riepilogo'),
              const SizedBox(height: 8),
              Text(_title.text.trim().isEmpty ? '—' : _title.text.trim(),
                  style: Typo.display(20)),
              const SizedBox(height: 4),
              Text(
                widget.workout
                    ? '$_kind · ${_days.length} giorni · $_durationWeeks settimane'
                    : '$_mode · $_kind · ${_days.length} giornate',
                style: Typo.mono(11, FontWeight.w600, Palette.textMid),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        NeonButton('Assegna ad atleti',
            color: _accent, loading: _saving, onTap: () => _finalize('assign')),
        const SizedBox(height: 10),
        NeonButton('Salva come template',
            filled: false,
            color: _accent,
            onTap: () => _finalize('template')),
        const SizedBox(height: 10),
        NeonButton('Salva bozza',
            filled: false,
            color: Palette.textMid,
            onTap: () => _finalize('draft')),
      ],
    );
  }
}

class _FoodPickerSheet extends ConsumerStatefulWidget {
  const _FoodPickerSheet({required this.onPick});

  final void Function(FoodDto) onPick;

  @override
  ConsumerState<_FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends ConsumerState<_FoodPickerSheet> {
  final _query = TextEditingController();
  List<FoodDto> _results = [];

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
    try {
      final res = await ref
          .read(apiClientProvider)
          .coachSearchFoods(_query.text.trim());
      if (mounted) setState(() => _results = res.results);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(title: Text('Alimenti', style: Typo.display(18))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.screenH),
            child: TextField(
              controller: _query,
              style: Typo.body(15, FontWeight.w500),
              decoration:
                  const InputDecoration(hintText: 'Cerca un alimento…'),
              onChanged: (_) => _load(),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final f = _results[i];
                return ListTile(
                  title: Text(f.name,
                      style: Typo.body(14.5, FontWeight.w600)),
                  subtitle: Text(
                      '${f.kcal.toInt()} kcal · P ${f.protein.toInt()} C ${f.carb.toInt()} F ${f.fat.toInt()} (100 g)',
                      style: Typo.mono(
                          10, FontWeight.w600, Palette.textMid)),
                  onTap: () => widget.onPick(f),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
