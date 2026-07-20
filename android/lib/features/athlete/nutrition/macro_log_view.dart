import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/ring_gauge.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';
import 'food_search_sheet.dart';

/// MACRO-mode food diary — port of iOS `MacroLogView`: calorie ring
/// (amber when over), 3 macro bars, add-food flow, deletable entries,
/// optional day paging when opened from the weekly strip.
class MacroLogView extends ConsumerStatefulWidget {
  const MacroLogView({
    super.key,
    required this.assignmentId,
    this.logDate,
  });

  final int assignmentId;

  /// null = today.
  final DateTime? logDate;

  @override
  ConsumerState<MacroLogView> createState() => _MacroLogViewState();
}

class _MacroLogViewState extends ConsumerState<MacroLogView> {
  MacroDayDto? _day;
  bool _error = false;
  late DateTime? _date = widget.logDate;

  String? get _dateParam => _date == null
      ? null
      : '${_date!.year.toString().padLeft(4, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final day = await ref
          .read(apiClientProvider)
          .macroDay(widget.assignmentId, date: _dateParam);
      if (mounted) setState(() => _day = day);
    } catch (_) {
      if (mounted && _day == null) setState(() => _error = true);
    }
  }

  void _shiftDay(int delta) {
    Haptics.tap();
    setState(() {
      _date = (_date ?? DateTime.now()).add(Duration(days: delta));
      _day = null;
    });
    _load();
  }

  Future<void> _deleteEntry(MacroEntryDto entry) async {
    try {
      await ref.read(apiClientProvider).deleteMacroLog(entry.id);
      Haptics.thud();
      await _load();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Eliminazione non riuscita');
      }
    }
  }

  void _addFood() {
    showAppSheet<void>(
      context,
      builder: (_) => FoodSearchSheet(
        assignmentId: widget.assignmentId,
        date: _dateParam,
        onLogged: () {
          Haptics.success();
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    final showPager = widget.logDate != null;
    final title = _date == null
        ? 'Diario di oggi'
        : Formatters.weekdayLongDate(_date!);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          if (showPager)
            Row(
              children: [
                Pressable(
                  onTap: () => _shiftDay(-1),
                  child: const Icon(Icons.chevron_left_rounded, size: 28),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Eyebrow('Diario alimentare'),
                      FittedBox(
                        child:
                            Text(title, style: Typo.poster(26)),
                      ),
                    ],
                  ),
                ),
                Pressable(
                  onTap: () => _shiftDay(1),
                  child: const Icon(Icons.chevron_right_rounded, size: 28),
                ),
              ],
            )
          else
            ScreenHeader(
                eyebrow: 'Diario alimentare',
                title: 'Oggi',
                subtitle: Formatters.weekdayLongDate(DateTime.now())),
          if (day == null && !_error)
            const Shimmer(child: SkelCard(height: 260))
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else ...[
            _summary(day!),
            NeonButton(
              'Aggiungi alimento',
              icon: Icons.add_rounded,
              color: Palette.cyan,
              onTap: _addFood,
            ),
            if (day.entries.isEmpty)
              const EmptyPanel(
                icon: Icons.restaurant_outlined,
                message: 'Nessun alimento registrato per questo giorno.',
              )
            else
              for (final entry in day.entries) _entryRow(entry),
          ],
        ],
      ),
    );
  }

  Widget _summary(MacroDayDto day) {
    final over = day.consumed.kcal > day.target.kcal && day.target.kcal > 0;
    final ringColor = over ? Palette.amber : Palette.cyan;
    final progress = day.target.kcal <= 0
        ? 0.0
        : (day.consumed.kcal / day.target.kcal).clamp(0.0, 1.0);
    return VoltPanel(
      tint: ringColor.withValues(alpha: 0.35),
      child: Column(
        children: [
          RingGauge(
            progress: progress,
            size: 150,
            stroke: 12,
            color: ringColor,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${day.consumed.kcal.toInt()}',
                    style: Typo.poster(34)),
                Text('/ ${day.target.kcal.toInt()} KCAL',
                    style:
                        Typo.mono(9, FontWeight.w700, Palette.textLow)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _macroBar('Proteine', day.consumed.protein, day.target.protein,
              Palette.magenta),
          _macroBar(
              'Carboidrati', day.consumed.carb, day.target.carb, Palette.cyan),
          _macroBar('Grassi', day.consumed.fat, day.target.fat, Palette.lime),
        ],
      ),
    );
  }

  Widget _macroBar(
      String label, double consumed, double target, Color color) {
    final progress =
        target <= 0 ? 0.0 : (consumed / target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: Typo.body(12.5, FontWeight.w600))),
              Text('${consumed.toInt()} / ${target.toInt()} g',
                  style: Typo.mono(10.5, FontWeight.w600, Palette.textMid)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Palette.void2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryRow(MacroEntryDto entry) {
    return VoltPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: Typo.body(14.5, FontWeight.w600)),
                Text(
                  '${entry.mealName.isEmpty ? '' : '${entry.mealName} · '}${Formatters.decimal(entry.quantityG)} g · P ${entry.protein.toInt()} C ${entry.carbs.toInt()} F ${entry.fat.toInt()}',
                  style: Typo.mono(9.5, FontWeight.w600, Palette.textMid),
                ),
              ],
            ),
          ),
          Text('${entry.kcal.toInt()} kcal',
              style: Typo.mono(11.5, FontWeight.w700, Palette.amber)),
          const SizedBox(width: 8),
          Pressable(
            onTap: () => _deleteEntry(entry),
            child: const Icon(Icons.delete_outline_rounded,
                size: 18, color: Palette.crimson),
          ),
        ],
      ),
    );
  }
}
