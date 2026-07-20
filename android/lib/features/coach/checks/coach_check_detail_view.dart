import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Submitted-check review — port of iOS `CoachCheckDetailView`: client
/// header, sections (server-rendered values), photos, athlete notes,
/// feedback composer.
class CoachCheckDetailView extends ConsumerStatefulWidget {
  const CoachCheckDetailView({super.key, required this.checkId});

  final int checkId;

  @override
  ConsumerState<CoachCheckDetailView> createState() =>
      _CoachCheckDetailViewState();
}

class _CoachCheckDetailViewState extends ConsumerState<CoachCheckDetailView> {
  CoachCheckDetailDto? _detail;
  bool _error = false;
  final _feedback = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d =
          await ref.read(apiClientProvider).coachCheckDetail(widget.checkId);
      if (mounted) {
        setState(() {
          _detail = d;
          if (_feedback.text.isEmpty) _feedback.text = d.coachFeedback;
        });
      }
    } catch (_) {
      if (mounted && _detail == null) setState(() => _error = true);
    }
  }

  Future<void> _sendFeedback() async {
    final text = _feedback.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(apiClientProvider)
          .coachCheckFeedback(widget.checkId, text);
      if (mounted) {
        StatusFlash.show(context, success: true, message: 'Feedback inviato');
      }
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Invio non riuscito');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
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
                Row(
                  children: [
                    AvatarView(
                      url: d.client?.profileImageUrl,
                      name: d.client?.displayName ?? '?',
                      size: 52,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.client?.displayName ?? 'Atleta',
                              style: Typo.display(20)),
                          Text(
                            [
                              d.title,
                              if (Formatters.parseDate(d.submittedAt) != null)
                                Formatters.mediumDate(
                                    Formatters.parseDate(d.submittedAt)!),
                            ].join(' · '),
                            style: Typo.body(
                                12, FontWeight.w400, Palette.textMid),
                          ),
                        ],
                      ),
                    ),
                    if (d.weightKg != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${Formatters.decimal(d.weightKg!)} kg',
                              style: Typo.mono(
                                  15, FontWeight.w700, Palette.violet)),
                          if (d.weightDelta != null)
                            Text(
                              '${d.weightDelta! >= 0 ? '+' : ''}${Formatters.decimal(d.weightDelta!)}',
                              style: Typo.mono(
                                  10,
                                  FontWeight.w600,
                                  d.weightDelta! <= 0
                                      ? Palette.lime
                                      : Palette.amber),
                            ),
                        ],
                      ),
                  ],
                ),
                for (final section in d.sections) _sectionCard(section),
                if (d.photos.isNotEmpty)
                  VoltPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Foto'),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 110,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final p in d.photos)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      imageUrl: p.url,
                                      width: 84,
                                      height: 110,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, _, _) => Container(
                                          width: 84, color: Palette.void2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final (label, text, color) in [
                  ('Note', d.notes, Palette.cyan),
                  ('Infortuni', d.injuries, Palette.crimson),
                  ('Limitazioni', d.limitations, Palette.amber),
                ])
                  if ((text ?? '').isNotEmpty)
                    VoltPanel(
                      tint: color.withValues(alpha: 0.35),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(label),
                          const SizedBox(height: 6),
                          Text(text!,
                              style: Typo.body(13.5, FontWeight.w400)),
                        ],
                      ),
                    ),
                VoltPanel(
                  tint: Palette.violet.withValues(alpha: 0.4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('Il tuo feedback'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _feedback,
                        maxLines: 5,
                        minLines: 3,
                        style: Typo.body(14, FontWeight.w400),
                        decoration: InputDecoration(
                          hintText:
                              'Scrivi un feedback per il tuo atleta…',
                          hintStyle: Typo.body(
                              14, FontWeight.w400, Palette.textLow),
                        ),
                      ),
                      const SizedBox(height: 12),
                      NeonButton('Invia feedback',
                          color: Palette.violet,
                          compact: true,
                          loading: _sending,
                          onTap: _sendFeedback),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionCard(Map<String, dynamic> section) {
    final label = (section['label'] as String?) ?? 'Sezione';
    final questions =
        (section['questions'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    if (questions.isEmpty) return const SizedBox.shrink();
    return VoltPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(label),
          const SizedBox(height: 10),
          for (final q in questions) _questionRow(q),
        ],
      ),
    );
  }

  Widget _questionRow(Map<String, dynamic> q) {
    final label = (q['label'] as String?) ?? '';
    final unit = q['unit'] as String?;
    final value = q['value'];
    final delta = (q['delta'] as num?)?.toDouble();
    final sides = (q['sides'] as List?)?.cast<Map<String, dynamic>>();

    if (sides != null && sides.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style:
                        Typo.body(13, FontWeight.w500, Palette.textMid))),
            for (final side in sides)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  '${side['tag'] ?? ''} ${side['value'] ?? '—'}',
                  style: Typo.mono(12, FontWeight.w700),
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
              child: Text(label,
                  style: Typo.body(13, FontWeight.w500, Palette.textMid))),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${value ?? '—'}${unit == null ? '' : ' $unit'}',
                  style: Typo.body(13.5, FontWeight.w700)),
              if (delta != null && delta != 0)
                Text(
                  '${delta > 0 ? '+' : ''}${Formatters.decimal(delta)}',
                  style: Typo.mono(10, FontWeight.w600,
                      delta > 0 ? Palette.lime : Palette.crimson),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
