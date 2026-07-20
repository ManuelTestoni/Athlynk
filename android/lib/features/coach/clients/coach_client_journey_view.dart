import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/confirm_dialog.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Coach-editable "Percorso" — port of iOS `CoachJourneyView`: the athlete's
/// timeline plus CRUD on coaching phases.
class CoachClientJourneyView extends ConsumerStatefulWidget {
  const CoachClientJourneyView({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  final int clientId;
  final String clientName;

  @override
  ConsumerState<CoachClientJourneyView> createState() =>
      _CoachClientJourneyViewState();
}

class _CoachClientJourneyViewState
    extends ConsumerState<CoachClientJourneyView> {
  JourneyResponse? _res;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res =
          await ref.read(apiClientProvider).coachClientJourney(widget.clientId);
      if (mounted) setState(() => _res = res);
    } catch (_) {
      if (mounted && _res == null) setState(() => _error = true);
    }
  }

  Future<void> _openPhaseSheet({JourneyPhaseDto? phase}) async {
    await showAppSheet<void>(
      context,
      heightFactor: 0.78,
      builder: (_) => _PhaseSheet(
        phase: phase,
        onSubmit: (body) async {
          try {
            if (phase == null) {
              await ref
                  .read(apiClientProvider)
                  .coachCreatePhase(widget.clientId, body);
            } else {
              await ref
                  .read(apiClientProvider)
                  .coachUpdatePhase(widget.clientId, phase.id, body);
            }
            await _load();
            return true;
          } catch (_) {
            return false;
          }
        },
      ),
    );
  }

  Future<void> _deletePhase(JourneyPhaseDto phase) async {
    final ok = await ConfirmCenter.confirm(
      context,
      ConfirmOptions(
        title: 'Eliminare la fase "${phase.title}"?',
        icon: Icons.delete_outline_rounded,
        variant: ConfirmVariant.danger,
        confirmLabel: 'Elimina',
      ),
    );
    if (!ok) return;
    try {
      await ref
          .read(apiClientProvider)
          .coachDeletePhase(widget.clientId, phase.id);
      await _load();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Eliminazione non riuscita');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Nuova fase',
            icon: Icon(Icons.flag_rounded, color: Palette.phase),
            onPressed: () => _openPhaseSheet(),
          ),
        ],
      ),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          ScreenHeader(
              eyebrow: widget.clientName, title: 'Percorso', titleSize: 34),
          if (res == null && !_error)
            const TimelineSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else ...[
            if (res!.phases.isNotEmpty) ...[
              const Eyebrow('Fasi', color: Palette.phase),
              for (final p in res.phases)
                VoltPanel(
                  tint: Palette.phase.withValues(alpha: 0.45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(p.title, style: Typo.display(17))),
                          Pressable(
                            onTap: () => _openPhaseSheet(phase: p),
                            child: const Icon(Icons.edit_outlined,
                                size: 17, color: Palette.textMid),
                          ),
                          const SizedBox(width: 12),
                          Pressable(
                            onTap: () => _deletePhase(p),
                            child: const Icon(Icons.delete_outline_rounded,
                                size: 17, color: Palette.crimson),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${p.durationValue} ${p.durationUnit == 'MONTHS' ? 'mesi' : 'settimane'} · da ${Formatters.parseDate(p.start) == null ? '—' : Formatters.mediumDate(Formatters.parseDate(p.start)!)}',
                        style:
                            Typo.mono(10, FontWeight.w600, Palette.textMid),
                      ),
                      if (p.note.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(p.note,
                            style: Typo.body(
                                13, FontWeight.w400, Palette.textMid)),
                      ],
                    ],
                  ),
                ),
            ],
            const Eyebrow('Eventi'),
            if (res.events.isEmpty)
              const EmptyPanel(
                  icon: Icons.map_outlined,
                  message: 'Il percorso è appena iniziato.')
            else
              for (final e in res.events)
                VoltPanel(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        switch (e.type) {
                          'allenamento' => Icons.fitness_center_rounded,
                          'nutrizione' => Icons.restaurant_rounded,
                          _ => Icons.verified_rounded,
                        },
                        size: 17,
                        color: switch (e.type) {
                          'allenamento' => Palette.cyan,
                          'nutrizione' => Palette.lime,
                          _ => Palette.violet,
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title,
                                style: Typo.body(14, FontWeight.w600)),
                            Text(
                              Formatters.parseDate(e.date) == null
                                  ? ''
                                  : Formatters.mediumDate(
                                      Formatters.parseDate(e.date)!),
                              style: Typo.mono(
                                  9.5, FontWeight.w600, Palette.textLow),
                            ),
                          ],
                        ),
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

class _PhaseSheet extends StatefulWidget {
  const _PhaseSheet({this.phase, required this.onSubmit});

  final JourneyPhaseDto? phase;
  final Future<bool> Function(Map<String, dynamic>) onSubmit;

  @override
  State<_PhaseSheet> createState() => _PhaseSheetState();
}

class _PhaseSheetState extends State<_PhaseSheet> {
  late final _title = TextEditingController(text: widget.phase?.title ?? '');
  late final _note = TextEditingController(text: widget.phase?.note ?? '');
  late DateTime _start = widget.phase == null
      ? DateTime.now()
      : (Formatters.parseDate(widget.phase!.start) ?? DateTime.now());
  late int _durationValue = widget.phase?.durationValue ?? 4;
  late String _durationUnit = widget.phase?.durationUnit ?? 'WEEKS';
  bool _saving = false;

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final ok = await widget.onSubmit({
      'title': _title.text.trim(),
      'note': _note.text.trim(),
      'start_date':
          '${_start.year.toString().padLeft(4, '0')}-${_start.month.toString().padLeft(2, '0')}-${_start.day.toString().padLeft(2, '0')}',
      'duration_value': _durationValue,
      'duration_unit': _durationUnit,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
          title: Text(widget.phase == null ? 'Nuova fase' : 'Modifica fase',
              style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          TextField(
              controller: _title,
              style: Typo.body(15, FontWeight.w600),
              decoration:
                  const InputDecoration(labelText: 'Titolo (es. Massa)')),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Inizio', style: Typo.body(14, FontWeight.w600)),
            trailing: Text(Formatters.mediumDate(_start),
                style: Typo.mono(13, FontWeight.w600, Palette.phase)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _start,
                firstDate:
                    DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _start = picked);
            },
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _durationValue.toDouble(),
                  min: 1,
                  max: 24,
                  divisions: 23,
                  activeColor: Palette.phase,
                  onChanged: (v) =>
                      setState(() => _durationValue = v.round()),
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  '$_durationValue ${_durationUnit == 'MONTHS' ? 'mesi' : 'sett.'}',
                  style: Typo.mono(13, FontWeight.w700),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final (v, l) in const [
                ('WEEKS', 'Settimane'),
                ('MONTHS', 'Mesi')
              ])
                ChoiceChip(
                  label: Text(l, style: Typo.body(13, FontWeight.w600)),
                  selected: _durationUnit == v,
                  selectedColor: Palette.phase.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => _durationUnit = v),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
              controller: _note,
              maxLines: 3,
              style: Typo.body(14, FontWeight.w400),
              decoration: const InputDecoration(labelText: 'Nota')),
          const SizedBox(height: 22),
          NeonButton('Salva',
              color: Palette.phase, loading: _saving, onTap: _save),
        ],
      ),
    );
  }
}
