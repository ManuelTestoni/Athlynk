import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/session_detail_view.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';

/// Past sessions grouped by month — port of iOS `WorkoutHistoryView`,
/// 20 per page.
class WorkoutHistoryView extends ConsumerStatefulWidget {
  const WorkoutHistoryView({super.key});

  @override
  ConsumerState<WorkoutHistoryView> createState() =>
      _WorkoutHistoryViewState();
}

class _WorkoutHistoryViewState extends ConsumerState<WorkoutHistoryView> {
  List<WorkoutSessionDto>? _sessions;
  bool _error = false;
  bool _hasMore = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).workoutHistory();
      if (mounted) {
        setState(() {
          _sessions = res.sessions;
          _hasMore = res.hasMore ?? false;
        });
      }
    } catch (_) {
      if (mounted && _sessions == null) setState(() => _error = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await ref
          .read(apiClientProvider)
          .workoutHistory(offset: _sessions?.length ?? 0);
      if (mounted) {
        setState(() {
          _sessions = [...?_sessions, ...res.sessions];
          _hasMore = res.hasMore ?? false;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(
              eyebrow: 'Le tue sessioni', title: 'Storico'),
          if (sessions == null && !_error)
            const DateCardsSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (sessions!.isEmpty)
            const EmptyPanel(
              icon: Icons.history_rounded,
              message: 'Nessuna sessione registrata: inizia ad allenarti!',
            )
          else ...[
            for (final (i, s) in sessions.indexed) ...[
              if (i == 0 || !_sameMonth(sessions[i - 1], s))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Eyebrow(_monthLabel(s)),
                ),
              _sessionCard(s),
            ],
            if (_hasMore)
              LoadMoreButton(onTap: _loadMore, loading: _loadingMore),
          ],
        ],
      ),
    );
  }

  bool _sameMonth(WorkoutSessionDto a, WorkoutSessionDto b) {
    final da = Formatters.parseDate(a.startedAt);
    final db = Formatters.parseDate(b.startedAt);
    if (da == null || db == null) return true;
    return da.year == db.year && da.month == db.month;
  }

  String _monthLabel(WorkoutSessionDto s) {
    final d = Formatters.parseDate(s.startedAt);
    return d == null ? 'Sessioni' : Formatters.monthYear(d);
  }

  Widget _sessionCard(WorkoutSessionDto s) {
    final d = Formatters.parseDate(s.startedAt)?.toLocal();
    return VoltPanel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SessionDetailScreen(
          loader: () =>
              ref.read(apiClientProvider).workoutSessionDetail(s.id),
        ),
      )),
      child: Row(
        children: [
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Palette.magenta.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(d == null ? '—' : '${d.day}', style: Typo.poster(20)),
                if (d != null)
                  Text(
                    Formatters.monthYear(d).split(' ').first.toUpperCase(),
                    style: Typo.mono(7.5, FontWeight.w700, Palette.textMid),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.dayLabel, style: Typo.body(15, FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  [
                    if (s.durationMinutes != null) '${s.durationMinutes} min',
                    if (s.avgRpe != null)
                      'RPE ${Formatters.decimal(s.avgRpe!)}',
                    '${s.setCount} serie',
                  ].join(' · '),
                  style: Typo.mono(10.5, FontWeight.w600, Palette.textMid),
                ),
              ],
            ),
          ),
          Icon(
            s.interrupted
                ? Icons.pause_circle_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 20,
            color: s.interrupted ? Palette.amber : Palette.lime,
          ),
        ],
      ),
    );
  }
}
