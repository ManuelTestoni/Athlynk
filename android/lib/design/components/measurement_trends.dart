import 'package:flutter/material.dart';

import '../../core/l10n/formatters.dart';
import '../theme.dart';
import 'charts.dart';
import 'panel.dart';
import 'pressable.dart';

/// One raw measurement sample.
class MeasurementSample {
  const MeasurementSample({required this.date, required this.value});
  final DateTime date;
  final double value;
}

/// ISO-week mean aggregation — ported from the web's `check_progress.js`
/// weekly logic (same numbers as iOS `weeklyMeans`).
List<({DateTime weekStart, double mean})> weeklyMeans(
    List<MeasurementSample> samples) {
  if (samples.isEmpty) return const [];
  final byWeek = <DateTime, List<double>>{};
  for (final s in samples) {
    final monday = DateTime(s.date.year, s.date.month, s.date.day)
        .subtract(Duration(days: s.date.weekday - 1));
    byWeek.putIfAbsent(monday, () => []).add(s.value);
  }
  final keys = byWeek.keys.toList()..sort();
  return [
    for (final k in keys)
      (
        weekStart: k,
        mean: byWeek[k]!.reduce((a, b) => a + b) / byWeek[k]!.length,
      ),
  ];
}

/// Italian labels for ISAK measurement sites (subset used across screens —
/// unknown keys fall back to a prettified key).
String measurementSiteLabel(String key) {
  const labels = {
    'neck': 'Collo',
    'shoulders': 'Spalle',
    'chest': 'Torace',
    'waist': 'Vita',
    'abdomen': 'Addome',
    'hips': 'Fianchi',
    'arm_relaxed_l': 'Braccio ril. SX',
    'arm_relaxed_r': 'Braccio ril. DX',
    'arm_flexed_l': 'Braccio contr. SX',
    'arm_flexed_r': 'Braccio contr. DX',
    'forearm_l': 'Avambraccio SX',
    'forearm_r': 'Avambraccio DX',
    'wrist_l': 'Polso SX',
    'wrist_r': 'Polso DX',
    'thigh_l': 'Coscia SX',
    'thigh_r': 'Coscia DX',
    'mid_thigh_l': 'Coscia media SX',
    'mid_thigh_r': 'Coscia media DX',
    'calf_l': 'Polpaccio SX',
    'calf_r': 'Polpaccio DX',
    'ankle_l': 'Caviglia SX',
    'ankle_r': 'Caviglia DX',
    'triceps': 'Tricipite',
    'biceps': 'Bicipite',
    'subscapular': 'Sottoscapolare',
    'iliac_crest': 'Cresta iliaca',
    'supraspinale': 'Sovraspinale',
    'abdominal': 'Addominale',
    'front_thigh': 'Coscia anteriore',
    'medial_calf': 'Polpaccio mediale',
    'chest_fold': 'Pettorale',
    'axillar': 'Ascellare',
  };
  final hit = labels[key];
  if (hit != null) return hit;
  return key
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// "Il mio andamento" — swipeable chart pages: bodyweight weekly means,
/// circumferences (site chips), skinfolds (site chips). Port of iOS
/// `MeasurementTrends`, shared by athlete (own data) and coach (per client).
class MeasurementTrends extends StatefulWidget {
  const MeasurementTrends({
    super.key,
    required this.weightSamples,
    required this.circumferenceSites,
    required this.skinfoldSites,
    required this.samplesForSite,
  });

  final List<MeasurementSample> weightSamples;
  final List<String> circumferenceSites;
  final List<String> skinfoldSites;

  /// `(isSkinfold, siteKey)` → samples.
  final List<MeasurementSample> Function(bool skinfold, String site)
      samplesForSite;

  @override
  State<MeasurementTrends> createState() => _MeasurementTrendsState();
}

class _MeasurementTrendsState extends State<MeasurementTrends> {
  final _controller = PageController();
  int _page = 0;
  String? _circSite;
  String? _skinSite;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _weightPage(),
      if (widget.circumferenceSites.isNotEmpty)
        _sitePage(false, widget.circumferenceSites, 'Circonferenze', 'cm'),
      if (widget.skinfoldSites.isNotEmpty)
        _sitePage(true, widget.skinfoldSites, 'Pliche', 'mm'),
    ];
    return Column(
      children: [
        SizedBox(
          height: 320,
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: pages,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pages.length; i++)
              AnimatedContainer(
                duration: Motion.snappyDuration,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? Palette.cyan : Palette.void2,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _weightPage() {
    final means = weeklyMeans(widget.weightSamples);
    final points = [
      for (final m in means)
        TrendPoint(
          value: double.parse(m.mean.toStringAsFixed(1)),
          label: Formatters.shortDate(m.weekStart),
        ),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: voltPanel(tint: Palette.cyan.withValues(alpha: 0.3)),
      padding: const EdgeInsets.all(Space.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Peso corporeo · media settimanale'),
          const SizedBox(height: 10),
          Expanded(
            child: points.length >= 2
                ? TrendChart(points: points, unit: 'kg', height: 240)
                : const _ChartEmpty(),
          ),
        ],
      ),
    );
  }

  Widget _sitePage(
      bool skinfold, List<String> sites, String title, String unit) {
    final selected =
        (skinfold ? _skinSite : _circSite) ?? sites.first;
    final samples = widget.samplesForSite(skinfold, selected);
    final points = [
      for (final s in samples)
        TrendPoint(value: s.value, label: Formatters.shortDate(s.date)),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: voltPanel(tint: Palette.violet.withValues(alpha: 0.3)),
      padding: const EdgeInsets.all(Space.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(title),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final site in sites)
                  Pressable(
                    onTap: () => setState(() {
                      if (skinfold) {
                        _skinSite = site;
                      } else {
                        _circSite = site;
                      }
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: site == selected
                            ? Palette.violet
                            : Palette.void0,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text(
                        measurementSiteLabel(site),
                        style: Typo.mono(
                            10,
                            FontWeight.w600,
                            site == selected
                                ? Palette.void0
                                : Palette.textMid),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: points.length >= 2
                ? TrendChart(
                    points: points,
                    unit: unit,
                    height: 200,
                    color: Palette.violet)
                : const _ChartEmpty(),
          ),
        ],
      ),
    );
  }
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Servono almeno due rilevazioni per il grafico.',
        style: Typo.body(13, FontWeight.w400, Palette.textLow),
      ),
    );
  }
}
