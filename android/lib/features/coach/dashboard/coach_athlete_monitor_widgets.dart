import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/charts.dart';
import '../../../design/components/panel.dart';
import '../../../design/theme.dart';

/// The "per atleta" dashboard widgets — parità con il web (athlete_body /
/// athlete_training / athlete_nutrition). Each has its own athlete dropdown
/// over the coach's active athletes and renders native charts (design-system
/// TrendChart / BarsChart) fed by the existing coach client endpoints.

/// Loads the active-athlete list and exposes the shared dropdown UI.
mixin _AthleteMonitorMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  List<CoachClientRow> clients = [];
  int? selectedId;
  bool clientsLoaded = false;

  Future<void> loadClients(int? initialId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.coachClients(limit: 200);
    if (!mounted) return;
    final active = resp.clients
        .where((c) => (c.status ?? 'ACTIVE').toUpperCase() == 'ACTIVE')
        .toList();
    setState(() {
      clients = active.isEmpty ? resp.clients : active;
      selectedId = initialId ?? (clients.isEmpty ? null : clients.first.id);
      clientsLoaded = true;
    });
  }

  Widget athletePicker(Color accent) {
    if (clients.isEmpty) return const SizedBox.shrink();
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: selectedId,
        isDense: true,
        dropdownColor: Palette.void1,
        style: Typo.body(13, FontWeight.w600),
        icon: Icon(Icons.expand_more_rounded, size: 16, color: accent),
        items: [
          for (final c in clients)
            DropdownMenuItem(value: c.id, child: Text(c.displayName)),
        ],
        onChanged: (v) {
          setState(() => selectedId = v);
          onAthleteChanged();
        },
      ),
    );
  }

  void onAthleteChanged();

  Widget panel({required Color tint, required List<Widget> children}) => Container(
        decoration: voltPanel(tint: tint.withValues(alpha: 0.35)),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget monitorHeader(String title, Color accent) => Row(
        children: [
          Expanded(child: Eyebrow(title)),
          athletePicker(accent),
        ],
      );

  Widget centeredHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: Typo.body(13, FontWeight.w400, Palette.textMid)),
        ),
      );
}

// ── Composizione atleta ──

class CoachAthleteBodyWidget extends ConsumerStatefulWidget {
  const CoachAthleteBodyWidget({super.key, this.initialClientId});
  final int? initialClientId;

  @override
  ConsumerState<CoachAthleteBodyWidget> createState() =>
      _CoachAthleteBodyWidgetState();
}

class _CoachAthleteBodyWidgetState extends ConsumerState<CoachAthleteBodyWidget>
    with _AthleteMonitorMixin {
  List<ProgressEntryDto> entries = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadClients(widget.initialClientId).then((_) => _loadData());
  }

  @override
  void onAthleteChanged() => _loadData();

  Future<void> _loadData() async {
    final id = selectedId;
    if (id == null) {
      setState(() => loading = false);
      return;
    }
    setState(() => loading = true);
    final resp = await ref.read(apiClientProvider).coachClientProgress(id);
    if (!mounted) return;
    setState(() {
      entries = resp.entries;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Entries arrive newest-first; plot the latest 12 oldest→newest.
    final recent = entries.take(12).toList().reversed.toList();
    final points = <TrendPoint>[
      for (final e in recent)
        if (e.weightKg != null)
          TrendPoint(
            value: e.weightKg!,
            label: (e.submittedAt ?? '').split('T').first,
          ),
    ];
    final latest = entries.isEmpty ? null : entries.first;
    return panel(tint: Palette.cyan, children: [
      monitorHeader('Composizione atleta', Palette.cyan),
      const SizedBox(height: 12),
      if (loading)
        const Center(child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: CircularProgressIndicator(strokeWidth: 2)))
      else if (points.length < 2)
        centeredHint('Nessuna rilevazione di peso per questo atleta.')
      else ...[
        Text('ANDAMENTO PESO',
            style: Typo.mono(9, FontWeight.w600, Palette.textMid)),
        const SizedBox(height: 6),
        TrendChart(points: points, color: Palette.cyan, unit: 'kg'),
        if (latest != null) ...[
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _measures('Circonferenze (cm)', latest.measurements)),
            const SizedBox(width: 16),
            Expanded(child: _measures('Pliche (mm)', latest.skinfolds)),
          ]),
        ],
      ],
    ]);
  }

  Widget _measures(String title, Map<String, String>? dict) {
    final map = dict ?? const {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title.toUpperCase(),
          style: Typo.mono(8, FontWeight.w600, Palette.textLow)),
      const SizedBox(height: 4),
      if (map.isEmpty)
        Text('—', style: Typo.body(12, FontWeight.w400, Palette.textLow))
      else
        for (final e in (map.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Expanded(child: Text(e.key,
                  style: Typo.body(11, FontWeight.w400, Palette.textMid))),
              Text(e.value, style: Typo.body(11, FontWeight.w600)),
            ]),
          ),
    ]);
  }
}

// ── Allenamento atleta (carico + volume) ──

class CoachAthleteTrainingWidget extends ConsumerStatefulWidget {
  const CoachAthleteTrainingWidget({super.key, this.initialClientId});
  final int? initialClientId;

  @override
  ConsumerState<CoachAthleteTrainingWidget> createState() =>
      _CoachAthleteTrainingWidgetState();
}

class _CoachAthleteTrainingWidgetState
    extends ConsumerState<CoachAthleteTrainingWidget> with _AthleteMonitorMixin {
  List<TrendPoint> loadPoints = [];
  List<double> volumeTotals = [];
  List<String> volumeLabels = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadClients(widget.initialClientId).then((_) => _loadData());
  }

  @override
  void onAthleteChanged() => _loadData();

  Future<void> _loadData() async {
    final id = selectedId;
    if (id == null) {
      setState(() => loading = false);
      return;
    }
    setState(() => loading = true);
    final api = ref.read(apiClientProvider);
    final loads = await api.coachClientLoads(id).catchError((_) => <String, dynamic>{});
    final volume = await api.coachClientVolume(id).catchError((_) => <String, dynamic>{});
    if (!mounted) return;
    final series = (loads['series'] as List?) ?? const [];
    final lp = <TrendPoint>[
      for (final s in series)
        if (s is Map && s['load_max'] != null)
          TrendPoint(
            value: (s['load_max'] as num).toDouble(),
            label: (s['date'] as String? ?? '').toString(),
          ),
    ];
    // Weekly volume = total reps across muscle groups per week.
    final weeks = ((volume['weeks'] as List?) ?? const []).cast<String>();
    final vSeries = (volume['series'] as Map?)?.cast<String, dynamic>() ?? {};
    final totals = <double>[];
    for (var i = 0; i < weeks.length; i++) {
      var sum = 0.0;
      for (final v in vSeries.values) {
        final list = (v as List?) ?? const [];
        if (i < list.length && list[i] != null) sum += (list[i] as num).toDouble();
      }
      totals.add(sum);
    }
    setState(() {
      loadPoints = lp;
      volumeTotals = totals;
      volumeLabels = [for (final w in weeks) w.length >= 5 ? w.substring(5) : w];
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return panel(tint: Palette.lime, children: [
      monitorHeader('Allenamento atleta', Palette.lime),
      const SizedBox(height: 12),
      if (loading)
        const Center(child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: CircularProgressIndicator(strokeWidth: 2)))
      else ...[
        Text('CARICO (TOP SET)',
            style: Typo.mono(9, FontWeight.w600, Palette.textMid)),
        const SizedBox(height: 6),
        if (loadPoints.length < 2)
          centeredHint('Nessun carico registrato per questo atleta.')
        else
          TrendChart(points: loadPoints, color: Palette.lime, unit: 'kg'),
        if (volumeTotals.length >= 2) ...[
          const SizedBox(height: 14),
          Text('VOLUME SETTIMANALE (REPS)',
              style: Typo.mono(9, FontWeight.w600, Palette.textMid)),
          const SizedBox(height: 6),
          BarsChart(
            values: volumeTotals.length > 8
                ? volumeTotals.sublist(volumeTotals.length - 8)
                : volumeTotals,
            labels: volumeLabels.length > 8
                ? volumeLabels.sublist(volumeLabels.length - 8)
                : volumeLabels,
            color: Palette.lime,
          ),
        ],
      ],
    ]);
  }
}

// ── Nutrizione atleta ──

class CoachAthleteNutritionWidget extends ConsumerStatefulWidget {
  const CoachAthleteNutritionWidget({super.key, this.initialClientId});
  final int? initialClientId;

  @override
  ConsumerState<CoachAthleteNutritionWidget> createState() =>
      _CoachAthleteNutritionWidgetState();
}

class _CoachAthleteNutritionWidgetState
    extends ConsumerState<CoachAthleteNutritionWidget> with _AthleteMonitorMixin {
  List<MacroHistoryDayDto> days = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadClients(widget.initialClientId).then((_) => _loadData());
  }

  @override
  void onAthleteChanged() => _loadData();

  Future<void> _loadData() async {
    final id = selectedId;
    if (id == null) {
      setState(() => loading = false);
      return;
    }
    setState(() => loading = true);
    final resp = await ref
        .read(apiClientProvider)
        .coachClientMacroHistory(id)
        .catchError((_) => const MacroHistoryResponse());
    if (!mounted) return;
    setState(() {
      days = resp.days;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recent = days.length > 8 ? days.sublist(days.length - 8) : days;
    final target = days.isNotEmpty ? days.last.target : null;
    return panel(tint: Palette.amber, children: [
      monitorHeader('Nutrizione atleta', Palette.amber),
      const SizedBox(height: 12),
      if (loading)
        const Center(child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: CircularProgressIndicator(strokeWidth: 2)))
      else if (recent.isEmpty)
        centeredHint("Nessun pasto registrato dall'atleta negli ultimi giorni.")
      else ...[
        if (target != null)
          Row(children: [
            _macroTile('kcal', target.kcal),
            _macroTile('Prot', target.protein),
            _macroTile('Carb', target.carb),
            _macroTile('Gras', target.fat),
          ]),
        const SizedBox(height: 10),
        Text('KCAL REGISTRATE · ULTIMI GIORNI',
            style: Typo.mono(9, FontWeight.w600, Palette.textMid)),
        const SizedBox(height: 6),
        BarsChart(
          values: [for (final d in recent) d.consumed.kcal],
          labels: [for (final d in recent) d.dowShort],
          color: Palette.amber,
          maxValue: target != null && target.kcal > 0 ? target.kcal * 1.2 : null,
        ),
      ],
    ]);
  }

  Widget _macroTile(String label, double value) => Expanded(
        child: Column(children: [
          Text(value > 0 ? value.toInt().toString() : '—',
              style: Typo.display(18)),
          Text(label, style: Typo.mono(8, FontWeight.w600, Palette.textLow)),
        ]),
      );
}
