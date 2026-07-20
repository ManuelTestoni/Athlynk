import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/charts.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/ring_gauge.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';

/// Business analytics — port of iOS `CoachAnalyticsView`: KPI grid, at-risk
/// client cards with reason chips, review-rate ring, check-volume bars.
class CoachAnalyticsView extends ConsumerStatefulWidget {
  const CoachAnalyticsView({super.key});

  @override
  ConsumerState<CoachAnalyticsView> createState() =>
      _CoachAnalyticsViewState();
}

class _CoachAnalyticsViewState extends ConsumerState<CoachAnalyticsView> {
  CoachAnalyticsDto? _analytics;
  CoachBusinessKpis? _business;
  List<CoachRiskClient> _risk = [];
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
        api.coachAnalytics(),
        api
            .coachAnalyticsBusiness()
            .then<Object?>((v) => v)
            .catchError((_) => null),
        api
            .coachAnalyticsRisk()
            .then<Object?>((v) => v.clients)
            .catchError((_) => const <CoachRiskClient>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _analytics = results[0] as CoachAnalyticsDto;
        _business = results[1] as CoachBusinessKpis?;
        _risk = results[2] as List<CoachRiskClient>;
      });
    } catch (_) {
      if (mounted && _analytics == null) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _analytics;
    final b = _business;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Il tuo business', title: 'Analisi'),
          if (a == null && !_error)
            const ListCardsSkeleton(count: 3, height: 130)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else ...[
            if (b != null)
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _kpi('${b.atRiskClientsCount}', 'A rischio',
                      Palette.crimson),
                  _kpi('${b.renewalsDue7d}', 'Rinnovi 7gg', Palette.amber),
                  _kpi(
                      b.monthlyRevenue == null
                          ? '—'
                          : Formatters.price(b.monthlyRevenue!),
                      'Ricavi mese',
                      Palette.lime),
                  _kpi(
                      b.churnRate30d == null
                          ? '—'
                          : '${(b.churnRate30d! * 100).toStringAsFixed(1)}%',
                      'Churn 30gg',
                      Palette.violet),
                ],
              ),
            VoltPanel(
              child: Row(
                children: [
                  RingGauge(
                    progress: (a!.reviewRate).clamp(0, 1),
                    size: 92,
                    stroke: 9,
                    color: Palette.bronze,
                    center: Text('${(a.reviewRate * 100).round()}%',
                        style: Typo.mono(13, FontWeight.w700)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tasso di revisione check',
                            style: Typo.display(16)),
                        Text(
                          '${a.pendingChecks} check in attesa su ${a.activeClients} atleti attivi.',
                          style: Typo.body(
                              12.5, FontWeight.w400, Palette.textMid),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (a.checksPerWeek.isNotEmpty)
              VoltPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Check per settimana'),
                    const SizedBox(height: 12),
                    BarsChart(
                      values: [for (final p in a.checksPerWeek) p.value],
                      labels: [for (final p in a.checksPerWeek) p.label],
                      color: Palette.violet,
                    ),
                  ],
                ),
              ),
            if (_risk.isNotEmpty) ...[
              const Eyebrow('Atleti a rischio', color: Palette.crimson),
              for (final r in _risk.take(10)) _riskCard(r),
            ],
          ],
        ],
      ),
    );
  }

  Widget _kpi(String value, String label, Color color) {
    return Container(
      decoration: voltPanel(tint: color.withValues(alpha: 0.3)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(child: Text(value, style: Typo.poster(26))),
          const SizedBox(height: 4),
          Text(label.toUpperCase(),
              style: Typo.mono(8.5, FontWeight.w700, color)
                  .copyWith(letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _riskCard(CoachRiskClient r) {
    final color = switch (r.riskClass) {
      'high' => Palette.crimson,
      'medium' => Palette.amber,
      _ => Palette.lime,
    };
    return VoltPanel(
      tint: color.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarView(
                  url: r.profileImageUrl, name: r.displayName, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Text(r.displayName,
                    style: Typo.body(14.5, FontWeight.w700)),
              ),
              StatusBadge(
                switch (r.riskClass) {
                  'high' => 'Alto',
                  'medium' => 'Medio',
                  _ => 'Basso',
                },
                color: color,
              ),
            ],
          ),
          if (r.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final reason in r.reasons)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(reason.label,
                        style: Typo.mono(9.5, FontWeight.w600, color)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
