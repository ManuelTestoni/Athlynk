import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/add_measurement_sheet.dart';
import '../../../design/components/exercise_trend_card.dart';
import '../../../design/components/measurement_trends.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';
import 'check_history_detail_view.dart';

/// "Il mio andamento" — port of iOS `ProgressTrackerView`: measurement trend
/// charts, before/after photo comparator, submitted-check history, per-
/// exercise progress list, manual measurement entry.
class ProgressTrackerView extends ConsumerStatefulWidget {
  const ProgressTrackerView({super.key});

  @override
  ConsumerState<ProgressTrackerView> createState() =>
      _ProgressTrackerViewState();
}

class _ProgressTrackerViewState extends ConsumerState<ProgressTrackerView> {
  List<ProgressEntryDto>? _entries;
  MeasurementSitesDto _sites = const MeasurementSitesDto();
  List<ExerciseHistoryItemDto> _exercises = [];
  bool _error = false;
  bool _hasMore = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final results = await Future.wait<Object?>([
        api.progress(),
        api.measurementSites().then<Object?>((v) => v).catchError((_) => null),
        api.progressExercises().then<Object?>((v) => v).catchError((_) => null),
      ]);
      if (!mounted) return;
      final p = results[0] as ProgressResponse;
      setState(() {
        _entries = p.entries;
        _hasMore = p.hasMore;
        _sites = (results[1] as MeasurementSitesDto?) ?? _sites;
        _exercises =
            (results[2] as List<ExerciseHistoryItemDto>?) ?? _exercises;
      });
    } catch (_) {
      if (mounted && _entries == null) setState(() => _error = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await ref
          .read(apiClientProvider)
          .progress(offset: _entries?.length ?? 0);
      if (mounted) {
        setState(() {
          _entries = [...?_entries, ...res.entries];
          _hasMore = res.hasMore;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<MeasurementSample> get _weightSamples {
    final out = <MeasurementSample>[];
    for (final e in _entries ?? const <ProgressEntryDto>[]) {
      final d = Formatters.parseDate(e.submittedAt);
      final w = e.weightKg;
      if (d != null && w != null) {
        out.add(MeasurementSample(date: d, value: w));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  List<MeasurementSample> _samplesForSite(bool skinfold, String site) {
    final out = <MeasurementSample>[];
    for (final e in _entries ?? const <ProgressEntryDto>[]) {
      final d = Formatters.parseDate(e.submittedAt);
      final map = skinfold ? e.skinfolds : e.measurements;
      final raw = map?[site];
      final v = raw == null ? null : double.tryParse(raw);
      if (d != null && v != null) {
        out.add(MeasurementSample(date: d, value: v));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  Future<void> _openAddMeasurement() async {
    MeasurementCatalog catalog;
    try {
      catalog = await ref.read(apiClientProvider).measurementCatalog();
    } catch (_) {
      catalog = const MeasurementCatalog();
    }
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      heightFactor: 0.85,
      builder: (_) => AddMeasurementSheet(
        catalog: catalog,
        onSubmit: ({required type, siteKey, required value, required date}) async {
          try {
            await ref.read(apiClientProvider).addMeasurement(
                type: type, key: siteKey, value: value, date: date);
            await _load();
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
    final entries = _entries;
    final photoEntries = [
      for (final e in entries ?? const <ProgressEntryDto>[])
        if (e.photos.isNotEmpty) e,
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Nuova misurazione',
            icon: Icon(Icons.add_rounded, color: Palette.cyan),
            onPressed: _openAddMeasurement,
          ),
        ],
      ),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(
              eyebrow: 'Peso, circonferenze e pliche',
              title: 'Andamento'),
          if (entries == null && !_error)
            const Shimmer(child: SkelCard(height: 300))
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else ...[
            MeasurementTrends(
              weightSamples: _weightSamples,
              circumferenceSites: _sites.measurements,
              skinfoldSites: _sites.skinfolds,
              samplesForSite: _samplesForSite,
            ),
            if (photoEntries.length >= 2) _photoComparator(photoEntries),
            if (_exercises.isNotEmpty) ...[
              const SizedBox(height: 6),
              const SectionHeader(
                  title: 'Progressi per esercizio',
                  eyebrow: 'Storico movimenti'),
              for (final ex in _exercises.take(20))
                NavListRow(
                  title: ex.name,
                  subtitle: '${ex.sessionsCount} sessioni',
                  icon: Icons.fitness_center_rounded,
                  accent: Palette.magenta,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ExerciseTrendByNameView(name: ex.name),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 6),
            const SectionHeader(
                title: 'Storico check', eyebrow: 'Le tue rilevazioni'),
            if (entries!.isEmpty)
              const EmptyPanel(
                icon: Icons.query_stats_rounded,
                message:
                    'Ancora nessuna rilevazione: compila un check per iniziare.',
              )
            else ...[
              for (final e in entries) _entryCard(e),
              if (_hasMore)
                LoadMoreButton(onTap: _loadMore, loading: _loadingMore),
            ],
          ],
        ],
      ),
    );
  }

  Widget _photoComparator(List<ProgressEntryDto> photoEntries) {
    final first = photoEntries.last; // oldest
    final last = photoEntries.first; // newest
    Widget photo(ProgressEntryDto e, String label) {
      final url = e.photos.first.url;
      final d = Formatters.parseDate(e.submittedAt);
      return Expanded(
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: Palette.void2),
                  errorWidget: (_, _, _) => Container(
                    color: Palette.void2,
                    child: const Icon(Icons.photo_outlined,
                        color: Palette.textLow),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Eyebrow(label, color: Palette.textLow),
            if (d != null)
              Text(Formatters.mediumDate(d),
                  style: Typo.mono(10, FontWeight.w600, Palette.textMid)),
          ],
        ),
      );
    }

    return VoltPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Prima · Dopo'),
          const SizedBox(height: 12),
          Row(
            children: [
              photo(first, 'Prima'),
              const SizedBox(width: 12),
              photo(last, 'Dopo'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _entryCard(ProgressEntryDto e) {
    final d = Formatters.parseDate(e.submittedAt);
    return VoltPanel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CheckHistoryDetailView(responseId: e.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d == null ? 'Rilevazione' : Formatters.longDate(d),
                  style: Typo.body(15, FontWeight.w700),
                ),
              ),
              if (e.weightKg != null)
                Text('${Formatters.decimal(e.weightKg!)} kg',
                    style: Typo.mono(14, FontWeight.w700, Palette.cyan)),
            ],
          ),
          if (e.photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 74,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in e.photos)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: p.url,
                          width: 58,
                          height: 74,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              Container(color: Palette.void2, width: 58),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if ((e.coachFeedback ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.format_quote_rounded,
                    size: 15, color: Palette.goldText),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    e.coachFeedback!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Typo.body(13, FontWeight.w500, Palette.textMid),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Trend for one exercise by NAME — port of iOS `ExerciseTrendByNameView`.
class ExerciseTrendByNameView extends ConsumerWidget {
  const ExerciseTrendByNameView({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        children: [
          ScreenHeader(eyebrow: 'Progressione', title: name, titleSize: 30),
          ExerciseTrendCard(
            loader: () => ref.read(apiClientProvider).exerciseTrendByName(name),
          ),
        ],
      ),
    );
  }
}
