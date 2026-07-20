import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/add_measurement_sheet.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/charts.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/session_detail_view.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';
import '../checks/coach_check_detail_view.dart';
import 'coach_client_journey_view.dart';

/// Full client profile — port of iOS `CoachClientDetailView`: identity,
/// relationship, active assignments, drill-ins (progressi, percorso,
/// sessioni, check, diario macro), coach-side measurement entry.
class CoachClientDetailView extends ConsumerStatefulWidget {
  const CoachClientDetailView({super.key, required this.clientId});

  final int clientId;

  @override
  ConsumerState<CoachClientDetailView> createState() =>
      _CoachClientDetailViewState();
}

class _CoachClientDetailViewState
    extends ConsumerState<CoachClientDetailView> {
  CoachClientDetailDto? _detail;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref
          .read(apiClientProvider)
          .coachClientDetail(widget.clientId);
      if (mounted) setState(() => _detail = d);
    } catch (_) {
      if (mounted && _detail == null) setState(() => _error = true);
    }
  }

  Future<void> _addMeasurement() async {
    await showAppSheet<void>(
      context,
      heightFactor: 0.85,
      builder: (_) => AddMeasurementSheet(
        catalog: const MeasurementCatalog(),
        onSubmit: ({required type, siteKey, required value, required date}) async {
          try {
            await ref.read(apiClientProvider).coachAddClientMeasurement(
                widget.clientId,
                type: type,
                key: siteKey,
                value: value,
                date: date);
            return true;
          } catch (_) {
            if (mounted) {
              StatusFlash.show(context,
                  success: false, message: 'Salvataggio non riuscito');
            }
            return false;
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Nuova misurazione',
            icon: Icon(Icons.straighten_rounded, color: Palette.bronze),
            onPressed: _addMeasurement,
          ),
        ],
      ),
      body: d == null
          ? Padding(
              padding: const EdgeInsets.all(Space.screenH),
              child: _error
                  ? EmptyPanel.network(onCta: () {
                      setState(() => _error = false);
                      _load();
                    })
                  : const FormSkeleton(),
            )
          : ScreenScroll(
              topPadding: 0,
              spacing: Space.element,
              onRefresh: _load,
              children: [
                Row(
                  children: [
                    AvatarView(
                      url: d.client.profileImageUrl,
                      name: d.client.displayName,
                      size: 64,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.client.displayName, style: Typo.poster(28)),
                          Text(
                            [
                              if (d.client.sport != null) d.client.sport!,
                              if (d.client.email != null) d.client.email!,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Typo.body(
                                12, FontWeight.w400, Palette.textMid),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                VoltPanel(
                  child: Column(
                    children: [
                      _row(
                          'Relazione',
                          switch ((d.relationship?.relationshipType ?? '')
                              .toUpperCase()) {
                            'WORKOUT' => 'Allenamento',
                            'NUTRITION' => 'Nutrizione',
                            'FULL' => 'Full Coaching',
                            _ => '—',
                          }),
                      const Divider(height: 18),
                      _row('Scheda attiva', d.activeWorkout?.title ?? '—'),
                      const Divider(height: 18),
                      _row('Piano alimentare', d.activePlan?.title ?? '—'),
                      const Divider(height: 18),
                      _row(
                          'Abbonamento',
                          d.subscription?.planName == null
                              ? '—'
                              : '${d.subscription!.planName} (${d.subscription!.status ?? '—'})'),
                      const Divider(height: 18),
                      _row(
                          'Ultimo check',
                          Formatters.parseDate(d.lastCheckAt) == null
                              ? '—'
                              : Formatters.mediumDate(
                                  Formatters.parseDate(d.lastCheckAt)!)),
                    ],
                  ),
                ),
                const Eyebrow('Approfondisci'),
                NavListRow(
                  title: 'Progressi',
                  subtitle: 'KPI, aderenza e RPE',
                  icon: Icons.query_stats_rounded,
                  accent: Palette.bronze,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CoachClientProgressView(
                          clientId: widget.clientId,
                          clientName: d.client.displayName),
                    ),
                  ),
                ),
                NavListRow(
                  title: 'Percorso',
                  subtitle: 'Timeline e fasi',
                  icon: Icons.map_rounded,
                  accent: Palette.phase,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CoachClientJourneyView(
                          clientId: widget.clientId,
                          clientName: d.client.displayName),
                    ),
                  ),
                ),
                NavListRow(
                  title: 'Sessioni',
                  subtitle: 'Storico allenamenti svolti',
                  icon: Icons.history_rounded,
                  accent: Palette.cyan,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _ClientSessionsView(clientId: widget.clientId),
                    ),
                  ),
                ),
                NavListRow(
                  title: 'Check',
                  subtitle: '${d.pendingChecks} in attesa',
                  icon: Icons.verified_rounded,
                  accent: Palette.violet,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _ClientChecksView(clientId: widget.clientId),
                    ),
                  ),
                ),
                NavListRow(
                  title: 'Diario macro',
                  subtitle: 'Giorni registrati dall\'atleta',
                  icon: Icons.restaurant_rounded,
                  accent: Palette.lime,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _ClientMacroHistoryView(clientId: widget.clientId),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: Typo.body(13.5, FontWeight.w500, Palette.textMid))),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end,
              style: Typo.body(13.5, FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Native "Progressi" hub — KPI grid + weekly adherence bars + RPE trend.
class CoachClientProgressView extends ConsumerStatefulWidget {
  const CoachClientProgressView({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  final int clientId;
  final String clientName;

  @override
  ConsumerState<CoachClientProgressView> createState() =>
      _CoachClientProgressViewState();
}

class _CoachClientProgressViewState
    extends ConsumerState<CoachClientProgressView> {
  CoachProgressKpiDto? _kpi;
  List<AdherencePointDto> _adherence = [];
  List<RpePointDto> _rpe = [];
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final results = await Future.wait<Object?>([
        api.coachClientKpi(widget.clientId),
        api
            .coachClientAdherence(widget.clientId)
            .then<Object?>((v) => v)
            .catchError((_) => const <AdherencePointDto>[]),
        api
            .coachClientRpe(widget.clientId)
            .then<Object?>((v) => v)
            .catchError((_) => const <RpePointDto>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _kpi = results[0] as CoachProgressKpiDto;
        _adherence = results[1] as List<AdherencePointDto>;
        _rpe = results[2] as List<RpePointDto>;
      });
    } catch (_) {
      if (mounted && _kpi == null) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kpi = _kpi;
    final rpePoints = [
      for (final p in _rpe)
        if (p.value != null && Formatters.parseDate(p.date) != null)
          TrendPoint(
            value: p.value!,
            label: Formatters.shortDate(Formatters.parseDate(p.date)!),
          ),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          ScreenHeader(
              eyebrow: widget.clientName, title: 'Progressi', titleSize: 34),
          if (kpi == null && !_error)
            const ListCardsSkeleton(count: 3, height: 120)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else ...[
            Row(
              children: [
                _kpiTile('${kpi!.totalSessions}', 'Sessioni totali'),
                _kpiTile(Formatters.decimal(kpi.avgSetsPerSession),
                    'Serie/sessione'),
                _kpiTile('${kpi.streakDays}', 'Streak giorni'),
                _kpiTile(
                    kpi.overallAdherencePct == null
                        ? '—'
                        : '${kpi.overallAdherencePct!.round()}%',
                    'Aderenza'),
              ],
            ),
            if (_adherence.isNotEmpty)
              VoltPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Aderenza settimanale'),
                    const SizedBox(height: 12),
                    BarsChart(
                      values: [
                        for (final p in _adherence) p.done.toDouble()
                      ],
                      labels: [for (final p in _adherence) p.label],
                      color: Palette.bronze,
                    ),
                  ],
                ),
              ),
            if (rpePoints.length >= 2)
              VoltPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('RPE medio per sessione'),
                    const SizedBox(height: 10),
                    TrendChart(
                        points: rpePoints,
                        color: Palette.violet,
                        height: 170),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _kpiTile(String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: voltPanel(radius: 14),
        child: Column(
          children: [
            FittedBox(child: Text(value, style: Typo.poster(20))),
            const SizedBox(height: 3),
            Text(label.toUpperCase(),
                textAlign: TextAlign.center,
                style: Typo.mono(6.5, FontWeight.w700, Palette.textLow)
                    .copyWith(letterSpacing: 0.8)),
          ],
        ),
      ),
    );
  }
}

class _ClientSessionsView extends ConsumerStatefulWidget {
  const _ClientSessionsView({required this.clientId});
  final int clientId;

  @override
  ConsumerState<_ClientSessionsView> createState() =>
      _ClientSessionsViewState();
}

class _ClientSessionsViewState extends ConsumerState<_ClientSessionsView> {
  SessionBriefListDto? _res;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res =
          await ref.read(apiClientProvider).coachClientSessions(widget.clientId);
      if (mounted) setState(() => _res = res);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Allenamenti svolti', title: 'Sessioni'),
          if (res == null && !_error)
            const DateCardsSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (res!.sessions.isEmpty)
            const EmptyPanel(
                icon: Icons.history_rounded,
                message: 'Nessuna sessione registrata.')
          else
            for (final s in res.sessions)
              VoltPanel(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SessionDetailScreen(
                      loader: () =>
                          ref.read(apiClientProvider).coachSessionDetail(s.id),
                    ),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.dayName ?? 'Sessione',
                              style: Typo.body(14.5, FontWeight.w700)),
                          Text(
                            [
                              if (Formatters.parseDate(s.startedAt) != null)
                                Formatters.mediumDate(
                                    Formatters.parseDate(s.startedAt)!),
                              if (s.durationMinutes != null)
                                '${s.durationMinutes} min',
                              if (s.avgRpe != null)
                                'RPE ${Formatters.decimal(s.avgRpe!)}',
                            ].join(' · '),
                            style: Typo.mono(
                                10, FontWeight.w600, Palette.textMid),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      s.interrupted
                          ? Icons.pause_circle_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                      color: s.interrupted ? Palette.amber : Palette.lime,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ClientChecksView extends ConsumerStatefulWidget {
  const _ClientChecksView({required this.clientId});
  final int clientId;

  @override
  ConsumerState<_ClientChecksView> createState() => _ClientChecksViewState();
}

class _ClientChecksViewState extends ConsumerState<_ClientChecksView> {
  CoachChecksResponse? _res;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res =
          await ref.read(apiClientProvider).coachClientChecks(widget.clientId);
      if (mounted) setState(() => _res = res);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Storico', title: 'Check'),
          if (res == null && !_error)
            const DateCardsSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (res!.checks.isEmpty)
            const EmptyPanel(
                icon: Icons.verified_outlined,
                message: 'Nessun check per questo atleta.')
          else
            for (final c in res.checks)
              VoltPanel(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CoachCheckDetailView(checkId: c.id),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.title,
                              style: Typo.body(14.5, FontWeight.w700)),
                          if (Formatters.parseDate(c.submittedAt) != null)
                            Text(
                              Formatters.mediumDate(
                                  Formatters.parseDate(c.submittedAt)!),
                              style: Typo.mono(
                                  10, FontWeight.w600, Palette.textMid),
                            ),
                        ],
                      ),
                    ),
                    StatusBadge(c.reviewed ? 'Revisionato' : 'Da rivedere',
                        color: c.reviewed ? Palette.lime : Palette.amber),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ClientMacroHistoryView extends ConsumerStatefulWidget {
  const _ClientMacroHistoryView({required this.clientId});
  final int clientId;

  @override
  ConsumerState<_ClientMacroHistoryView> createState() =>
      _ClientMacroHistoryViewState();
}

class _ClientMacroHistoryViewState
    extends ConsumerState<_ClientMacroHistoryView> {
  MacroHistoryResponse? _res;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .coachClientMacroHistory(widget.clientId);
      if (mounted) setState(() => _res = res);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Diario alimentare', title: 'Macro'),
          if (res == null && !_error)
            const DateCardsSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (res!.days.isEmpty)
            const EmptyPanel(
                icon: Icons.restaurant_outlined,
                message: 'L\'atleta non ha ancora registrato pasti.')
          else
            for (final day in res.days)
              VoltPanel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Column(
                        children: [
                          Text(day.dowShort,
                              style: Typo.mono(
                                  9, FontWeight.w700, Palette.lime)),
                          Text(
                            Formatters.parseDate(day.date) == null
                                ? '—'
                                : '${Formatters.parseDate(day.date)!.day}',
                            style: Typo.poster(20),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${day.consumed.kcal.toInt()} / ${day.target.kcal.toInt()} kcal · ${day.entries.length} alimenti',
                        style: Typo.body(13.5, FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
