import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';

/// Read-only past submitted check — port of iOS `CheckHistoryDetailView`:
/// per-section questions (value+delta, paired DX/SX, attachments, and the
/// read-only Calcolo Fabbisogni summary), photos, notes, coach feedback.
class CheckHistoryDetailView extends ConsumerStatefulWidget {
  const CheckHistoryDetailView({super.key, required this.responseId});

  final int responseId;

  @override
  ConsumerState<CheckHistoryDetailView> createState() =>
      _CheckHistoryDetailViewState();
}

class _CheckHistoryDetailViewState
    extends ConsumerState<CheckHistoryDetailView> {
  CheckDetailDto? _detail;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d =
          await ref.read(apiClientProvider).checkDetail(widget.responseId);
      if (mounted) setState(() => _detail = d);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
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
              children: [
                ScreenHeader(
                  eyebrow: 'Check inviato',
                  title: d.title,
                  titleSize: 30,
                  subtitle: Formatters.parseDate(d.submittedAt) == null
                      ? null
                      : Formatters.longDate(
                          Formatters.parseDate(d.submittedAt)!),
                ),
                for (final section in d.sections) _sectionCard(section),
                if (d.photos.isNotEmpty) _photos(d.photos),
                if ((d.notes ?? '').isNotEmpty)
                  _noteCard('Note', d.notes!, Palette.cyan),
                if ((d.injuries ?? '').isNotEmpty)
                  _noteCard('Infortuni', d.injuries!, Palette.crimson),
                if ((d.limitations ?? '').isNotEmpty)
                  _noteCard('Limitazioni', d.limitations!, Palette.amber),
                if (d.coachFeedback.isNotEmpty)
                  VoltPanel(
                    tint: Palette.amber.withValues(alpha: 0.45),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Feedback del coach'),
                        const SizedBox(height: 8),
                        Text(d.coachFeedback,
                            style: Typo.body(14.5, FontWeight.w500)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _sectionCard(CheckSection section) {
    return VoltPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(section.label),
          const SizedBox(height: 10),
          for (final q in section.questions) _question(q),
        ],
      ),
    );
  }

  Widget _question(CheckSectionQuestion q) {
    if (q.fb != null) return _fabbisogniCard(q.fb!);
    if (q.sides != null && q.sides!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.label,
                style: Typo.body(13.5, FontWeight.w600, Palette.textMid)),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final side in q.sides!)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Palette.void0,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Column(
                        children: [
                          Text(side.tag ?? side.label,
                              style: Typo.mono(
                                  9, FontWeight.w700, Palette.textLow)),
                          const SizedBox(height: 4),
                          Text(
                            '${side.value?.display ?? "—"}${side.unit == null ? '' : ' ${side.unit}'}',
                            style: Typo.mono(15, FontWeight.w700),
                          ),
                          if (side.delta != null)
                            Text(
                              '${side.delta! >= 0 ? '+' : ''}${Formatters.decimal(side.delta!)}',
                              style: Typo.mono(
                                  10,
                                  FontWeight.w600,
                                  side.delta! == 0
                                      ? Palette.textLow
                                      : (side.delta! > 0
                                          ? Palette.lime
                                          : Palette.crimson)),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    if (q.files != null && q.files!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.label,
                style: Typo.body(13.5, FontWeight.w600, Palette.textMid)),
            const SizedBox(height: 6),
            SizedBox(
              height: 74,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final f in q.files!)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: f.url,
                          width: 58,
                          height: 74,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Container(
                              width: 58,
                              color: Palette.void2,
                              child: const Icon(Icons.insert_drive_file_outlined,
                                  size: 18, color: Palette.textLow)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(q.label,
                style: Typo.body(13.5, FontWeight.w500, Palette.textMid)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${q.value?.display ?? "—"}${q.unit == null ? '' : ' ${q.unit}'}',
                style: Typo.body(14, FontWeight.w700),
              ),
              if (q.delta != null && q.delta != 0)
                Text(
                  '${q.delta! > 0 ? '+' : ''}${Formatters.decimal(q.delta!)}',
                  style: Typo.mono(10, FontWeight.w600,
                      q.delta! > 0 ? Palette.lime : Palette.crimson),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fabbisogniCard(CheckFabbisogni fb) {
    Widget row(String label, String? value) => value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                    child: Text(label,
                        style: Typo.body(
                            13, FontWeight.w500, Palette.textMid))),
                Text(value, style: Typo.body(13, FontWeight.w700)),
              ],
            ),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.void0,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.goldText.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Calcolo Fabbisogni'),
          const SizedBox(height: 8),
          row('Metabolismo basale', fb.mb?.toString()),
          row('Formula', fb.formula?.display),
          row('PAL', fb.pal?.display),
          row('DET finale', fb.detFinale == null ? null : '${fb.detFinale} kcal'),
          if (fb.macros.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final m in fb.macros)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(m.label,
                            style: Typo.body(13, FontWeight.w600))),
                    Text(
                      '${m.g ?? "—"} g · ${m.kcal ?? "—"} kcal',
                      style: Typo.mono(12, FontWeight.w600, Palette.textMid),
                    ),
                  ],
                ),
              ),
          ],
          row('Fibra', fb.fibra?.display),
          row('Apporto idrico', fb.idrico?.display),
        ],
      ),
    );
  }

  Widget _photos(List<CheckDetailPhoto> photos) {
    return VoltPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Foto progresso'),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in photos)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: p.url,
                        width: 84,
                        height: 110,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            Container(width: 84, color: Palette.void2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteCard(String title, String body, Color accent) {
    return VoltPanel(
      tint: accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(title),
          const SizedBox(height: 6),
          Text(body, style: Typo.body(14, FontWeight.w400)),
        ],
      ),
    );
  }
}
