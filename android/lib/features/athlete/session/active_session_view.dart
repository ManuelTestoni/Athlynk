import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../../design/components/confirm_dialog.dart';
import '../../../design/components/exercise_picker_sheet.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/ring_gauge.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import 'rest_timer.dart';
import 'rest_timer_overlay.dart';

/// Live workout logger — port of iOS `ActiveSessionView`/`ActiveSessionVM`,
/// the richest screen in the athlete app: per-set logging with validation
/// shake, session-only add/remove/substitute deviations, resume of open
/// sessions, rest timer, incomplete-finish alert.
class ActiveSessionView extends ConsumerStatefulWidget {
  const ActiveSessionView({
    super.key,
    required this.assignmentId,
    required this.day,
  });

  final int assignmentId;
  final WorkoutDayDto day;

  @override
  ConsumerState<ActiveSessionView> createState() => _ActiveSessionViewState();
}

class _SetEntry {
  final reps = TextEditingController();
  final load = TextEditingController();
  final rpe = TextEditingController();
  bool done = false;
  bool invalidReps = false;
  bool invalidLoad = false;
  int shakes = 0;

  void dispose() {
    reps.dispose();
    load.dispose();
    rpe.dispose();
  }
}

class _ActiveSessionViewState extends ConsumerState<ActiveSessionView> {
  int? _sessionId;
  List<SessionExerciseDto> _exercises = [];
  final Map<String, int> _setCounts = {};
  final Map<String, _SetEntry> _entries = {};
  bool _loading = true;
  bool _failed = false;
  bool _finished = false;
  bool _finishing = false;

  // Session-only deviations.
  final Set<int> _removed = {};
  final Map<int, int> _substituted = {};
  final List<int> _added = [];

  @override
  void initState() {
    super.initState();
    ref.read(sessionControllerProvider.notifier).setTabBarHidden(true);
    _start();
  }

  @override
  void dispose() {
    for (final e in _entries.values) {
      e.dispose();
    }
    ref.read(sessionControllerProvider.notifier).setTabBarHidden(false);
    super.dispose();
  }

  _SetEntry _entry(String exerciseKey, int setNumber) =>
      _entries.putIfAbsent('$exerciseKey-$setNumber', () => _SetEntry());

  Future<void> _start() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .sessionStart(widget.assignmentId, widget.day.id);
      if (!mounted) return;
      setState(() {
        _sessionId = res.sessionId;
        _exercises = res.exercises;
        for (final ex in res.exercises) {
          _setCounts[ex.key] = ex.sets;
          if (ex.removed) {
            final weId = ex.workoutExerciseId;
            if (weId != null) _removed.add(weId);
          }
          final sub = ex.substitutedWith;
          final weId = ex.workoutExerciseId;
          if (sub != null && weId != null) _substituted[weId] = sub.id;
          if (ex.added && ex.exerciseId != null) _added.add(ex.exerciseId!);
        }
        // Resume already-logged sets.
        for (final logged in res.setsLogged) {
          final e = _entry(logged.exerciseKey, logged.setNumber);
          e.done = logged.completed;
          if (logged.repsDone != null) e.reps.text = '${logged.repsDone}';
          if (logged.loadUsed != null) {
            e.load.text = Formatters.decimal(logged.loadUsed!);
          }
          if (logged.rpe != null) e.rpe.text = '${logged.rpe}';
          final key = logged.exerciseKey;
          if (logged.setNumber > (_setCounts[key] ?? 0)) {
            _setCounts[key] = logged.setNumber;
          }
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _toggleSet(SessionExerciseDto ex, int setNumber) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final e = _entry(ex.key, setNumber);

    if (!e.done) {
      // Validate before completing (shake + highlight on invalid).
      final reps = int.tryParse(e.reps.text.trim());
      final load = Formatters.parseDecimal(e.load.text);
      final invalidReps = e.reps.text.trim().isEmpty || reps == null;
      final invalidLoad = e.load.text.trim().isNotEmpty && load == null;
      if (invalidReps || invalidLoad) {
        Haptics.soft();
        setState(() {
          e.invalidReps = invalidReps;
          e.invalidLoad = invalidLoad;
          e.shakes++;
        });
        return;
      }
      setState(() {
        e.done = true;
        e.invalidReps = false;
        e.invalidLoad = false;
      });
      Haptics.thud();
      final rec = ex.recoverySeconds ?? 0;
      if (rec > 0) {
        ref
            .read(restTimerProvider.notifier)
            .start(seconds: rec, exerciseName: ex.displayName);
      }
      try {
        await ref.read(apiClientProvider).logSet(
              sessionId: sessionId,
              workoutExerciseId: ex.workoutExerciseId,
              addedExerciseId: ex.workoutExerciseId == null ? ex.exerciseId : null,
              setNumber: setNumber,
              reps: reps,
              load: load,
              loadUnit: ex.loadUnit ?? 'KG',
              rpe: int.tryParse(e.rpe.text.trim()),
              completed: true,
              isExtraSet: setNumber > ex.sets,
              substituted: ex.substitutedWith != null,
              actualExerciseId: ex.substitutedWith?.id,
            );
      } catch (_) {
        // Roll back the optimistic toggle on network failure.
        if (mounted) setState(() => e.done = false);
      }
    } else {
      setState(() => e.done = false);
      try {
        await ref.read(apiClientProvider).logSet(
              sessionId: sessionId,
              workoutExerciseId: ex.workoutExerciseId,
              addedExerciseId: ex.workoutExerciseId == null ? ex.exerciseId : null,
              setNumber: setNumber,
              reps: int.tryParse(e.reps.text.trim()),
              load: Formatters.parseDecimal(e.load.text),
              loadUnit: ex.loadUnit ?? 'KG',
              rpe: int.tryParse(e.rpe.text.trim()),
              completed: false,
            );
      } catch (_) {}
    }
  }

  void _pushOverrides() {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    // Fire-and-forget, like iOS.
    ref.read(apiClientProvider).setSessionOverrides(
          sessionId: sessionId,
          removed: _removed.toList(),
          substituted: _substituted,
          added: _added,
        );
  }

  void _addExercise() {
    showAppSheet<void>(
      context,
      builder: (_) => ExercisePickerSheet(
        search: ref.read(apiClientProvider).searchExercises,
        onPick: (picked) {
          Navigator.of(context, rootNavigator: false).pop();
          setState(() {
            final ex = SessionExerciseDto.addedExercise(
              catalogId: picked.id,
              name: picked.name,
              targetMuscleGroup: picked.primaryMuscle,
              coverImage: picked.coverImage,
              demoGif: picked.demoGif,
            );
            _exercises = [..._exercises, ex];
            _setCounts[ex.key] = ex.sets;
            _added.add(picked.id);
          });
          Haptics.thud();
          _pushOverrides();
        },
      ),
    );
  }

  void _substitute(SessionExerciseDto ex) {
    final weId = ex.workoutExerciseId;
    if (weId == null) return;
    showAppSheet<void>(
      context,
      builder: (_) => ExercisePickerSheet(
        title: 'Sostituisci esercizio',
        similarTo: ex.exerciseCatalogId,
        search: ref.read(apiClientProvider).searchExercises,
        onPick: (picked) {
          Navigator.of(context, rootNavigator: false).pop();
          setState(() {
            _substituted[weId] = picked.id;
            _exercises = [
              for (final e in _exercises)
                if (e.key == ex.key)
                  e.copyWith(
                      substitutedWith: SubstituteExerciseDto(
                          id: picked.id, name: picked.name))
                else
                  e,
            ];
          });
          Haptics.thud();
          _pushOverrides();
        },
      ),
    );
  }

  Future<void> _removeExercise(SessionExerciseDto ex) async {
    final weId = ex.workoutExerciseId;
    final confirmed = await ConfirmCenter.confirm(
      context,
      const ConfirmOptions(
        title: 'Elimina da questa sessione',
        subtitle:
            'L\'esercizio resta nella scheda: lo togli solo da questa sessione.',
        icon: Icons.delete_outline_rounded,
        variant: ConfirmVariant.danger,
        confirmLabel: 'Elimina',
      ),
    );
    if (!confirmed) return;
    setState(() {
      if (weId != null) {
        _removed.add(weId);
        _exercises = [
          for (final e in _exercises)
            if (e.key == ex.key) e.copyWith(removed: true) else e,
        ];
      } else {
        _exercises = [for (final e in _exercises) if (e.key != ex.key) e];
        if (ex.exerciseId != null) _added.remove(ex.exerciseId);
      }
    });
    Haptics.thud();
    _pushOverrides();
  }

  void _restoreExercise(SessionExerciseDto ex) {
    final weId = ex.workoutExerciseId;
    if (weId == null) return;
    setState(() {
      _removed.remove(weId);
      _exercises = [
        for (final e in _exercises)
          if (e.key == ex.key) e.copyWith(removed: false) else e,
      ];
    });
    _pushOverrides();
  }

  int _completedSets(SessionExerciseDto ex) {
    var done = 0;
    final count = _setCounts[ex.key] ?? ex.sets;
    for (var s = 1; s <= count; s++) {
      if (_entry(ex.key, s).done) done++;
    }
    return done;
  }

  Future<void> _finish({required bool interrupted}) async {
    final sessionId = _sessionId;
    if (sessionId == null || _finishing) return;
    if (!interrupted) {
      final unfinished = _exercises
          .where((e) => !e.removed && _completedSets(e) == 0)
          .length;
      if (unfinished > 0) {
        final ok = await ConfirmCenter.confirm(
          context,
          ConfirmOptions(
            title: 'Sessione incompleta',
            subtitle:
                'Hai ancora $unfinished ${unfinished == 1 ? "esercizio" : "esercizi"} da completare. I dati non compilati non verranno salvati.',
            icon: Icons.warning_amber_rounded,
            variant: ConfirmVariant.danger,
            confirmLabel: 'Termina comunque',
            cancelLabel: 'Continua',
          ),
        );
        if (!ok) return;
      }
    }
    setState(() => _finishing = true);
    ref.read(restTimerProvider.notifier).cancel();
    try {
      await ref
          .read(apiClientProvider)
          .finishSession(sessionId, interrupted: interrupted);
      Haptics.success();
      if (!mounted) return;
      if (interrupted) {
        Navigator.of(context).pop();
      } else {
        setState(() => _finished = true);
      }
    } catch (_) {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _exercises;
    final totalSets = visible
        .where((e) => !e.removed)
        .fold<int>(0, (s, e) => s + (_setCounts[e.key] ?? e.sets));
    final doneSets = visible
        .where((e) => !e.removed)
        .fold<int>(0, (s, e) => s + _completedSets(e));
    final progress = totalSets == 0 ? 0.0 : doneSets / totalSets;

    return PopScope(
      canPop: _finished || _failed,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await ConfirmCenter.confirm(
          context,
          const ConfirmOptions(
            title: 'Uscire dalla sessione?',
            subtitle: 'La sessione resta aperta: potrai riprenderla entro 6 ore.',
            icon: Icons.logout_rounded,
            confirmLabel: 'Esci',
          ),
        );
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text('SESSIONE ATTIVA',
                style: Typo.mono(12, FontWeight.w700, Palette.magenta)
                    .copyWith(letterSpacing: 3)),
            actions: [
              if (!_finished && !_loading && !_failed)
                TextButton(
                  onPressed: () => _finish(interrupted: true),
                  child: Text('Interrompi',
                      style:
                          Typo.body(13, FontWeight.w600, Palette.textLow)),
                ),
            ],
          ),
          body: Stack(
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(Space.screenH),
                  child: ListCardsSkeleton(count: 4, height: 150),
                )
              else if (_failed)
                Padding(
                  padding: const EdgeInsets.all(Space.screenH),
                  child: EmptyPanel.network(onCta: () {
                    setState(() {
                      _failed = false;
                      _loading = true;
                    });
                    _start();
                  }),
                )
              else if (_finished)
                _successPanel()
              else
                ScreenScroll(
                  topPadding: 4,
                  spacing: Space.element,
                  bottomPadding: 170,
                  children: [
                    Row(
                      children: [
                        RingGauge(
                          progress: progress,
                          size: 58,
                          stroke: 6,
                          color: Palette.magenta,
                          center: Text('${(progress * 100).round()}%',
                              style: Typo.mono(10, FontWeight.w700)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.day.focusArea ?? widget.day.label,
                                  style: Typo.display(20)),
                              Text('$doneSets/$totalSets serie completate',
                                  style: Typo.mono(11, FontWeight.w600,
                                      Palette.textMid)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    for (final ex in visible)
                      ex.removed ? _removedRow(ex) : _exerciseCard(ex),
                    NeonButton(
                      'Aggiungi esercizio',
                      filled: false,
                      color: Palette.cyan,
                      icon: Icons.add_rounded,
                      onTap: _addExercise,
                    ),
                    const SizedBox(height: 4),
                    NeonButton(
                      'TERMINA SESSIONE',
                      color: Palette.lime,
                      loading: _finishing,
                      onTap: () => _finish(interrupted: false),
                    ),
                  ],
                ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: RestTimerOverlay(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _successPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: VoltPanel(
          tint: Palette.lime.withValues(alpha: 0.5),
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_rounded,
                  size: 44, color: Palette.lime),
              const SizedBox(height: 14),
              Text('SESSIONE SALVATA',
                  style: Typo.mono(14, FontWeight.w700, Palette.lime)
                      .copyWith(letterSpacing: 2)),
              const SizedBox(height: 8),
              Text('Ottimo lavoro. Il coach vedrà i tuoi dati.',
                  textAlign: TextAlign.center,
                  style: Typo.body(14, FontWeight.w400, Palette.textMid)),
              const SizedBox(height: 20),
              NeonButton('Chiudi',
                  compact: true,
                  onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _removedRow(SessionExerciseDto ex) {
    return Container(
      decoration: voltPanel(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              ex.name,
              style: Typo.body(13.5, FontWeight.w500, Palette.textLow)
                  .copyWith(decoration: TextDecoration.lineThrough),
            ),
          ),
          TextButton(
            onPressed: () => _restoreExercise(ex),
            child: Text('Ripristina',
                style: Typo.body(13, FontWeight.w700, Palette.cyan)),
          ),
        ],
      ),
    );
  }

  Widget _exerciseCard(SessionExerciseDto ex) {
    final count = _setCounts[ex.key] ?? ex.sets;
    final substituted = ex.substitutedWith != null;
    return Container(
      decoration: voltPanel(
          tint: ex.added
              ? Palette.amber.withValues(alpha: 0.4)
              : Palette.magenta.withValues(alpha: 0.3)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExerciseThumb(url: ex.coverImage),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (substituted)
                      Text(ex.name,
                          style: Typo.body(11, FontWeight.w500, Palette.textLow)
                              .copyWith(
                                  decoration: TextDecoration.lineThrough)),
                    Text(ex.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Typo.body(15.5, FontWeight.w700)),
                    Row(
                      children: [
                        Text('${ex.reps} reps · rec ${ex.recoverySeconds ?? 0}s',
                            style: Typo.mono(
                                10, FontWeight.w600, Palette.textMid)),
                        if (ex.added) ...[
                          const SizedBox(width: 6),
                          const StatusBadge('Aggiunto', color: Palette.amber),
                        ],
                        if (substituted) ...[
                          const SizedBox(width: 6),
                          StatusBadge('Sostituito', color: Palette.cyan),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    size: 18, color: Palette.textMid),
                color: Palette.void0,
                onSelected: (v) {
                  switch (v) {
                    case 'sub':
                      _substitute(ex);
                    case 'del':
                      _removeExercise(ex);
                  }
                },
                itemBuilder: (_) => [
                  if (ex.workoutExerciseId != null)
                    PopupMenuItem(
                        value: 'sub',
                        child: Text('Sostituisci esercizio',
                            style: Typo.body(14, FontWeight.w500))),
                  PopupMenuItem(
                      value: 'del',
                      child: Text('Elimina da questa sessione',
                          style: Typo.body(
                              14, FontWeight.w500, Palette.crimson))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 34),
              Expanded(
                  child: Text('REPS',
                      textAlign: TextAlign.center,
                      style: Typo.mono(8, FontWeight.w700, Palette.textLow))),
              Expanded(
                  child: Text('CARICO',
                      textAlign: TextAlign.center,
                      style: Typo.mono(8, FontWeight.w700, Palette.textLow))),
              Expanded(
                  child: Text('RPE',
                      textAlign: TextAlign.center,
                      style: Typo.mono(8, FontWeight.w700, Palette.textLow))),
              const SizedBox(width: 40),
            ],
          ),
          for (var s = 1; s <= count; s++) _setRow(ex, s),
          Row(
            children: [
              Pressable(
                onTap: count > 1
                    ? () => setState(() => _setCounts[ex.key] = count - 1)
                    : null,
                child: Icon(Icons.remove_circle_outline_rounded,
                    size: 20,
                    color: count > 1 ? Palette.textMid : Palette.void2),
              ),
              const SizedBox(width: 10),
              Pressable(
                onTap: () => setState(() => _setCounts[ex.key] = count + 1),
                child: const Icon(Icons.add_circle_outline_rounded,
                    size: 20, color: Palette.textMid),
              ),
              const Spacer(),
              Text('${_completedSets(ex)}/$count',
                  style: Typo.mono(10, FontWeight.w700, Palette.textMid)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _setRow(SessionExerciseDto ex, int setNumber) {
    final e = _entry(ex.key, setNumber);
    final extra = setNumber > ex.sets;
    return _Shake(
      shakes: e.shakes,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                extra ? '+$setNumber' : '$setNumber',
                style: Typo.mono(11, FontWeight.w700,
                    extra ? Palette.amber : Palette.textLow),
              ),
            ),
            Expanded(child: _setField(e.reps, e.invalidReps, e.done)),
            const SizedBox(width: 6),
            Expanded(child: _setField(e.load, e.invalidLoad, e.done)),
            const SizedBox(width: 6),
            Expanded(child: _setField(e.rpe, false, e.done)),
            const SizedBox(width: 8),
            Pressable(
              haptic: false,
              onTap: () => _toggleSet(ex, setNumber),
              child: AnimatedContainer(
                duration: Motion.snappyDuration,
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: e.done ? Palette.lime : Colors.transparent,
                  border: Border.all(
                      color: e.done ? Palette.lime : Palette.textLow,
                      width: 2),
                ),
                child: e.done
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Palette.void0)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setField(
      TextEditingController controller, bool invalid, bool done) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: done ? Palette.lime.withValues(alpha: 0.07) : Palette.void0,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: invalid
                ? Palette.magenta
                : (done ? Palette.lime.withValues(alpha: 0.4) : Palette.line),
            width: invalid ? 1.6 : 1),
      ),
      child: TextField(
        controller: controller,
        enabled: !done,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: Typo.mono(13, FontWeight.w700),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 9),
        ),
      ),
    );
  }
}

/// Sine-wave horizontal shake (iOS `ShakeEffect`) — retriggers when
/// [shakes] increments.
class _Shake extends StatelessWidget {
  const _Shake({required this.shakes, required this.child});

  final int shakes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(shakes),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      builder: (context, t, child) {
        final dx = shakes == 0 ? 0.0 : math.sin(t * math.pi * 5) * 6 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: child,
    );
  }
}
