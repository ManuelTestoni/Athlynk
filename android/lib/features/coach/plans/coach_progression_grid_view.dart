import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Manual per-week progression grid — port of iOS `CoachProgressionGridView`
/// (1:1 with the web Step-3 editor): per-exercise week cells
/// (serie/reps/carico/recupero/RIR-RPE), tap a cell to edit, only dirty
/// metrics POSTed via the same web endpoint.
class CoachProgressionGridView extends ConsumerStatefulWidget {
  const CoachProgressionGridView({
    super.key,
    required this.planId,
    required this.days,
  });

  final int planId;
  final List<WorkoutDayDto> days;

  @override
  ConsumerState<CoachProgressionGridView> createState() =>
      _CoachProgressionGridViewState();
}

class _CoachProgressionGridViewState
    extends ConsumerState<CoachProgressionGridView> {
  late WorkoutDayDto _day = widget.days.first;
  Map<String, dynamic>? _grid;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _grid = null;
      _error = false;
    });
    try {
      final grid = await ref
          .read(apiClientProvider)
          .progressionGrid(widget.planId, _day.id);
      if (mounted) setState(() => _grid = grid);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _editCell(Map<String, dynamic> exercise, int week,
      Map<String, dynamic> cell) async {
    await showAppSheet<void>(
      context,
      heightFactor: 0.7,
      builder: (sheetContext) => _CellEditor(
        exerciseName: (exercise['name'] as String?) ?? 'Esercizio',
        week: week,
        cell: cell,
        onSave: (values) async {
          try {
            await ref.read(apiClientProvider).saveProgressionCell(
              widget.planId,
              {
                'workout_exercise_id': exercise['workout_exercise_id'] ??
                    exercise['id'],
                'week': week,
                ...values,
              },
            );
            if (sheetContext.mounted) {
              Navigator.of(sheetContext, rootNavigator: true).pop();
            }
            await _load();
          } catch (_) {
            if (mounted) {
              StatusFlash.show(context,
                  success: false, message: 'Salvataggio non riuscito');
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grid = _grid;
    final exercises =
        (grid?['exercises'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    final weeks = (grid?['weeks'] as num?)?.toInt() ??
        ((grid?['week_count'] as num?)?.toInt() ?? 8);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        children: [
          const ScreenHeader(
              eyebrow: 'Programmazione', title: 'Progressioni'),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final d in widget.days)
                  Pressable(
                    onTap: () {
                      setState(() => _day = d);
                      _load();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            d.id == _day.id ? Palette.cyan : Palette.void1,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text(d.label,
                          style: Typo.body(
                              12.5,
                              FontWeight.w600,
                              d.id == _day.id
                                  ? Palette.void0
                                  : Palette.textMid)),
                    ),
                  ),
              ],
            ),
          ),
          if (grid == null && !_error)
            const ListCardsSkeleton(count: 3, height: 110)
          else if (_error)
            EmptyPanel.network(onCta: _load)
          else if (exercises.isEmpty)
            const EmptyPanel(
              icon: Icons.grid_on_rounded,
              message:
                  'Nessun esercizio nel giorno selezionato (o la scheda non è una Programmazione).',
            )
          else
            for (final ex in exercises)
              VoltPanel(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((ex['name'] as String?) ?? 'Esercizio',
                        style: Typo.body(14.5, FontWeight.w700)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var w = 1; w <= weeks; w++)
                            _weekCell(ex, w),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _weekCell(Map<String, dynamic> ex, int week) {
    final cells =
        (ex['cells'] as Map?)?.cast<String, dynamic>() ??
            (ex['weeks'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final cell =
        (cells['$week'] as Map?)?.cast<String, dynamic>() ?? const {};
    final active = cell.isNotEmpty;
    return Pressable(
      onTap: () => _editCell(ex, week, cell),
      child: Container(
        width: 84,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: active
              ? Palette.cyan.withValues(alpha: 0.1)
              : Palette.void0,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active
                  ? Palette.cyan.withValues(alpha: 0.5)
                  : Palette.line),
        ),
        child: Column(
          children: [
            Text('SETT $week',
                style: Typo.mono(7.5, FontWeight.w700, Palette.textLow)),
            const SizedBox(height: 4),
            Text(
              '${cell['sets'] ?? '—'}×${cell['reps'] ?? '—'}',
              style: Typo.mono(12, FontWeight.w700),
            ),
            Text(
              cell['load'] == null ? '—' : '${cell['load']} kg',
              style: Typo.mono(9.5, FontWeight.w600, Palette.textMid),
            ),
          ],
        ),
      ),
    );
  }
}

class _CellEditor extends StatefulWidget {
  const _CellEditor({
    required this.exerciseName,
    required this.week,
    required this.cell,
    required this.onSave,
  });

  final String exerciseName;
  final int week;
  final Map<String, dynamic> cell;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  final Map<String, dynamic> _dirty = {};
  bool _saving = false;

  Widget _field(String label, String key, {bool text = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: widget.cell[key]?.toString() ?? '',
        keyboardType: text ? TextInputType.text : TextInputType.number,
        style: Typo.mono(15, FontWeight.w700),
        decoration: InputDecoration(labelText: label),
        onChanged: (v) => _dirty[key] =
            text ? v : (num.tryParse(v.replaceAll(',', '.'))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
        title: Text('${widget.exerciseName} · Sett. ${widget.week}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Typo.display(16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          _field('Serie', 'sets'),
          _field('Ripetizioni', 'reps', text: true),
          _field('Carico (kg)', 'load'),
          _field('Recupero (s)', 'recovery'),
          _field('RIR', 'rir'),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Palette.cyan,
                padding: const EdgeInsets.symmetric(vertical: 15)),
            onPressed: _saving || _dirty.isEmpty
                ? null
                : () async {
                    setState(() => _saving = true);
                    await widget.onSave(_dirty);
                    if (mounted) setState(() => _saving = false);
                  },
            child: Text(_saving ? 'Salvo…' : 'Salva settimana',
                style: Typo.body(15, FontWeight.w700, Palette.void0)),
          ),
        ],
      ),
    );
  }
}
