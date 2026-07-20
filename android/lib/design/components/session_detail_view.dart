import 'package:flutter/material.dart';

import '../../core/l10n/formatters.dart';
import '../../core/models/session.dart';
import '../theme.dart';
import 'panel.dart';
import 'scaffold.dart';
import 'skeleton.dart';

/// Shared read-only past-session detail (prescribed vs logged sets) — port
/// of iOS `SessionDetailView`, used by both apps via an injected loader.
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.loader});

  final Future<SessionDetailDto> Function() loader;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  SessionDetailDto? _detail;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.loader();
      if (mounted) setState(() => _detail = d);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: d == null
          ? Padding(
              padding: const EdgeInsets.all(Space.screenH),
              child: _error
                  ? EmptyPanel.network(onCta: () {
                      setState(() => _error = false);
                      _load();
                    })
                  : const ListCardsSkeleton(count: 4, height: 120),
            )
          : ScreenScroll(
              topPadding: 0,
              spacing: Space.element,
              children: [
                ScreenHeader(
                  eyebrow: d.interrupted ? 'Interrotta' : 'Completata',
                  title: d.dayName ?? 'Sessione',
                  titleSize: 30,
                  subtitle: [
                    if (Formatters.parseDate(d.startedAt) != null)
                      Formatters.longDate(
                          Formatters.parseDate(d.startedAt)!.toLocal()),
                    if (d.durationMinutes != null)
                      '${d.durationMinutes} min',
                    if (d.avgRpe != null)
                      'RPE medio ${Formatters.decimal(d.avgRpe!)}',
                  ].join(' · '),
                ),
                for (final ex in d.exercises) _exerciseCard(ex),
                if ((d.notes ?? '').isNotEmpty)
                  VoltPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Note'),
                        const SizedBox(height: 6),
                        Text(d.notes!,
                            style: Typo.body(14, FontWeight.w400)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _exerciseCard(SessionLoggedExerciseDto ex) {
    return VoltPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ex.wasSubstituted)
                      Text(ex.exerciseName,
                          style: Typo.body(
                                  11, FontWeight.w500, Palette.textLow)
                              .copyWith(
                                  decoration: TextDecoration.lineThrough)),
                    Text(ex.performedName,
                        style: Typo.body(15, FontWeight.w700)),
                  ],
                ),
              ),
              if (ex.added) const StatusBadge('Aggiunto', color: Palette.amber),
              if (ex.wasSubstituted)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: StatusBadge('Sostituito', color: Palette.cyan),
                ),
            ],
          ),
          if ((ex.prescribedReps ?? '').isNotEmpty)
            Text('Prescritto: ${ex.prescribedReps}',
                style: Typo.mono(10, FontWeight.w600, Palette.textLow)),
          const SizedBox(height: 8),
          for (final set in ex.sets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text('${set.setNumber}',
                        style: Typo.mono(
                            11, FontWeight.w700, Palette.textLow)),
                  ),
                  Expanded(
                    child: Text(
                      '${set.repsDone ?? "—"} reps × ${set.loadUsed == null ? "—" : Formatters.decimal(set.loadUsed!)} ${set.loadUnit == 'BODYWEIGHT' ? 'BW' : 'kg'}',
                      style: Typo.mono(12, FontWeight.w600),
                    ),
                  ),
                  if (set.rpe != null)
                    Text('RPE ${set.rpe}',
                        style: Typo.mono(
                            10, FontWeight.w600, Palette.amber)),
                  const SizedBox(width: 8),
                  Icon(
                    set.completed
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 15,
                    color: set.completed ? Palette.lime : Palette.void2,
                  ),
                ],
              ),
            ),
          if ((ex.exerciseNote ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(ex.exerciseNote!,
                style: Typo.body(12.5, FontWeight.w400, Palette.textMid)),
          ],
        ],
      ),
    );
  }
}
