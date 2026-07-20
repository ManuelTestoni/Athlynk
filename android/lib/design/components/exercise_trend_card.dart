import 'package:flutter/material.dart';

import '../../core/l10n/formatters.dart';
import '../../core/models/session.dart';
import '../theme.dart';
import 'charts.dart';
import 'panel.dart';
import 'pressable.dart';
import 'scaffold.dart';
import 'skeleton.dart';

enum TrendMetric {
  topSet('Top set'),
  volume('Volume'),
  weightedAvg('Media pond.');

  const TrendMetric(this.label);
  final String label;
}

/// Self-loading per-exercise progress card — port of iOS `ExerciseTrendCard`.
/// The caller injects the loader so one UI serves athlete-own, by-name and
/// coach-per-client scopes.
class ExerciseTrendCard extends StatefulWidget {
  const ExerciseTrendCard({super.key, required this.loader});

  final Future<ExerciseTrendDto> Function() loader;

  @override
  State<ExerciseTrendCard> createState() => _ExerciseTrendCardState();
}

class _ExerciseTrendCardState extends State<ExerciseTrendCard> {
  ExerciseTrendDto? _trend;
  bool _error = false;
  TrendMetric _metric = TrendMetric.topSet;

  static const _tip =
      'Top set: carico massimo della sessione. Volume: somma di reps × carico. '
      'Media pond.: carico medio pesato sulle ripetizioni. Tieni premuto sul '
      'grafico per vedere i valori punto per punto.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.loader();
      if (mounted) setState(() => _trend = t);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  double? _valueOf(TrendSessionDto s) => switch (_metric) {
        TrendMetric.topSet => s.topSet,
        TrendMetric.volume => s.volume,
        TrendMetric.weightedAvg => s.weightedAvgLoad,
      };

  @override
  Widget build(BuildContext context) {
    final trend = _trend;
    if (_error) {
      return const EmptyPanel(
          icon: Icons.show_chart_rounded,
          message: 'Andamento non disponibile.');
    }
    if (trend == null) {
      return const Shimmer(child: SkelCard(height: 220));
    }
    if (!trend.hasData || trend.sessions.length < 2) {
      return const EmptyPanel(
        icon: Icons.show_chart_rounded,
        message:
            'Completa almeno due sessioni per vedere la progressione.',
      );
    }

    final unit = trend.exercise.loadUnit == 'KG' ? 'kg' : '';
    final points = <TrendPoint>[];
    for (final s in trend.sessions) {
      final v = _valueOf(s);
      final d = Formatters.parseDate(s.date);
      if (v == null || d == null) continue;
      points.add(TrendPoint(value: v, label: Formatters.shortDate(d)));
    }
    final delta = points.length >= 2
        ? points.last.value - points.first.value
        : 0.0;

    return Container(
      decoration: voltPanel(tint: Palette.magenta.withValues(alpha: 0.3)),
      padding: const EdgeInsets.all(Space.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow('Andamento'),
              const SizedBox(width: 6),
              const InfoTip(_tip),
              const Spacer(),
              DeltaPill(delta: delta, unit: ' $unit'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final m in TrendMetric.values)
                Expanded(
                  child: Pressable(
                    onTap: () => setState(() => _metric = m),
                    child: AnimatedContainer(
                      duration: Motion.snappyDuration,
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: m == _metric
                            ? Palette.magenta
                            : Palette.void0,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text(
                        m.label,
                        style: Typo.mono(
                            10,
                            FontWeight.w700,
                            m == _metric ? Palette.void0 : Palette.textMid),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TrendChart(
            points: points,
            unit: _metric == TrendMetric.volume ? '' : unit,
            color: Palette.magenta,
            height: 170,
          ),
          const SizedBox(height: 14),
          const Eyebrow('Ultime sessioni'),
          const SizedBox(height: 8),
          for (final s in trend.sessions.reversed.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Formatters.parseDate(s.date) == null
                        ? '—'
                        : Formatters.mediumDate(
                            Formatters.parseDate(s.date)!),
                    style: Typo.mono(10, FontWeight.w600, Palette.textLow),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final set in s.sets)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (set.isExtra ?? false)
                                ? Palette.amber.withValues(alpha: 0.12)
                                : Palette.void2,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '${set.reps ?? "—"}×${set.load == null ? "—" : Formatters.decimal(set.load!)}',
                            style: Typo.mono(
                                10,
                                FontWeight.w600,
                                (set.isExtra ?? false)
                                    ? Palette.amber
                                    : Palette.textMid),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
