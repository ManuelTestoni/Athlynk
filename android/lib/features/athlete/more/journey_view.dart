import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';

/// "Il mio percorso" — port of iOS `JourneyView`: merged timeline of
/// plan/diet/check events + coach-defined phases (flagged nodes), grouped by
/// month, filter chips.
class JourneyView extends ConsumerStatefulWidget {
  const JourneyView({super.key});

  @override
  ConsumerState<JourneyView> createState() => _JourneyViewState();
}

enum _JourneyFilter {
  tutto('Tutto'),
  allenamento('Allenamento'),
  nutrizione('Nutrizione'),
  check('Check'),
  fasi('Fasi');

  const _JourneyFilter(this.label);
  final String label;
}

sealed class _Node {
  DateTime get date;
}

class _EventNode extends _Node {
  _EventNode(this.event, this.date);
  final JourneyEventDto event;
  @override
  final DateTime date;
}

class _PhaseNode extends _Node {
  _PhaseNode(this.phase, this.date);
  final JourneyPhaseDto phase;
  @override
  final DateTime date;
}

class _JourneyViewState extends ConsumerState<JourneyView> {
  List<JourneyEventDto>? _events;
  List<JourneyPhaseDto> _phases = [];
  bool _error = false;
  bool _hasMore = false;
  bool _loadingMore = false;
  _JourneyFilter _filter = _JourneyFilter.tutto;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).journey();
      if (mounted) {
        setState(() {
          _events = res.events;
          _phases = res.phases;
          _hasMore = res.hasMore;
        });
      }
    } catch (_) {
      if (mounted && _events == null) setState(() => _error = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await ref
          .read(apiClientProvider)
          .journey(offset: _events?.length ?? 0);
      if (mounted) {
        setState(() {
          _events = [...?_events, ...res.events];
          _hasMore = res.hasMore;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<_Node> get _nodes {
    final nodes = <_Node>[];
    for (final e in _events ?? const <JourneyEventDto>[]) {
      final d = Formatters.parseDate(e.date);
      if (d == null) continue;
      final keep = switch (_filter) {
        _JourneyFilter.tutto => true,
        _JourneyFilter.allenamento => e.type == 'allenamento',
        _JourneyFilter.nutrizione => e.type == 'nutrizione',
        _JourneyFilter.check => e.type == 'check',
        _JourneyFilter.fasi => false,
      };
      if (keep) nodes.add(_EventNode(e, d));
    }
    if (_filter == _JourneyFilter.tutto || _filter == _JourneyFilter.fasi) {
      for (final p in _phases) {
        final d = Formatters.parseDate(p.start);
        if (d != null) nodes.add(_PhaseNode(p, d));
      }
    }
    nodes.sort((a, b) => b.date.compareTo(a.date));
    return nodes;
  }

  Color _eventColor(String type) => switch (type) {
        'allenamento' => Palette.magenta,
        'nutrizione' => Palette.lime,
        'check' => Palette.violet,
        _ => Palette.cyan,
      };

  @override
  Widget build(BuildContext context) {
    final nodes = _nodes;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Il mio percorso', title: 'Percorso'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _JourneyFilter.values) ...[
                  Pressable(
                    onTap: () => setState(() => _filter = f),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _filter == f
                            ? Palette.textHi
                            : Palette.void1,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text(
                        f.label,
                        style: Typo.body(13, FontWeight.w600,
                            _filter == f ? Palette.void0 : Palette.textMid),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_events == null && !_error)
            const TimelineSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (nodes.isEmpty)
            const EmptyPanel(
              icon: Icons.map_outlined,
              message: 'Il tuo percorso è appena iniziato.',
            )
          else ...[
            for (final (i, node) in nodes.indexed) ...[
              if (i == 0 ||
                  nodes[i - 1].date.month != node.date.month ||
                  nodes[i - 1].date.year != node.date.year)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Eyebrow(Formatters.monthYear(node.date)),
                ),
              RevealUp(index: i.clamp(0, 8), child: _nodeRow(node)),
            ],
            if (_hasMore)
              LoadMoreButton(onTap: _loadMore, loading: _loadingMore),
          ],
        ],
      ),
    );
  }

  Widget _nodeRow(_Node node) {
    switch (node) {
      case _EventNode(:final event, :final date):
        final color = _eventColor(event.type);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Palette.void0, width: 2),
                  boxShadow: neonGlow(color),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: voltPanel(tint: color.withValues(alpha: 0.3)),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Formatters.mediumDate(date),
                        style:
                            Typo.mono(10, FontWeight.w600, Palette.textLow)),
                    const SizedBox(height: 3),
                    Text(event.title, style: Typo.body(15, FontWeight.w700)),
                    if ((event.subtitle ?? '').isNotEmpty)
                      Text(event.subtitle!,
                          style: Typo.body(
                              12.5, FontWeight.w400, Palette.textMid)),
                    if ((event.statusLabel ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      StatusBadge(event.statusLabel!, color: color),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      case _PhaseNode(:final phase, :final date):
        final unitLabel =
            phase.durationUnit == 'MONTHS' ? 'mesi' : 'settimane';
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Icon(Icons.flag_rounded, size: 16, color: Palette.phase),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                decoration: voltPanel(
                    tint: Palette.phase.withValues(alpha: 0.5)),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('Fase · ${phase.durationValue} $unitLabel',
                        color: Palette.phase),
                    const SizedBox(height: 5),
                    Text(phase.title, style: Typo.display(17)),
                    Text(Formatters.mediumDate(date),
                        style:
                            Typo.mono(10, FontWeight.w600, Palette.textLow)),
                    if (phase.note.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(phase.note,
                          style: Typo.body(
                              13, FontWeight.w400, Palette.textMid)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }
}
