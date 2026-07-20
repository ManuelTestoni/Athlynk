import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import 'macro_log_view.dart';

/// Past MACRO days — port of iOS `MacroHistoryView`, 14 per page; tapping a
/// day opens the (editable) diary for that date.
class MacroHistoryView extends ConsumerStatefulWidget {
  const MacroHistoryView({super.key, required this.assignmentId});

  final int assignmentId;

  @override
  ConsumerState<MacroHistoryView> createState() => _MacroHistoryViewState();
}

class _MacroHistoryViewState extends ConsumerState<MacroHistoryView> {
  List<MacroHistoryDayDto>? _days;
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
      final res =
          await ref.read(apiClientProvider).macroHistory(widget.assignmentId);
      if (mounted) {
        setState(() {
          _days = res.days;
          _hasMore = res.hasMore;
        });
      }
    } catch (_) {
      if (mounted && _days == null) setState(() => _error = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await ref
          .read(apiClientProvider)
          .macroHistory(widget.assignmentId, offset: _days?.length ?? 0);
      if (mounted) {
        setState(() {
          _days = [...?_days, ...res.days];
          _hasMore = res.hasMore;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Diario alimentare', title: 'Storico'),
          if (days == null && !_error)
            const DateCardsSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (days!.isEmpty)
            const EmptyPanel(
              icon: Icons.calendar_view_day_outlined,
              message: 'Nessun giorno registrato finora.',
            )
          else ...[
            for (final day in days) _dayRow(day),
            if (_hasMore)
              LoadMoreButton(onTap: _loadMore, loading: _loadingMore),
          ],
        ],
      ),
    );
  }

  Widget _dayRow(MacroHistoryDayDto day) {
    final date = Formatters.parseDate(day.date);
    final over = day.consumed.kcal > day.target.kcal && day.target.kcal > 0;
    return VoltPanel(
      onTap: date == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => MacroLogView(
                  assignmentId: widget.assignmentId,
                  logDate: date,
                ),
              )),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Column(
              children: [
                Text(day.dowShort,
                    style: Typo.mono(9, FontWeight.w700, Palette.cyan)),
                Text(date == null ? '—' : '${date.day}',
                    style: Typo.poster(20)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${day.consumed.kcal.toInt()} / ${day.target.kcal.toInt()} kcal',
                  style: Typo.body(14.5, FontWeight.w700,
                      over ? Palette.amber : Palette.textHi),
                ),
                Text(
                  'P ${day.consumed.protein.toInt()} · C ${day.consumed.carb.toInt()} · F ${day.consumed.fat.toInt()} · ${day.entries.length} alimenti',
                  style: Typo.mono(9.5, FontWeight.w600, Palette.textMid),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 17, color: Palette.textLow),
        ],
      ),
    );
  }
}
