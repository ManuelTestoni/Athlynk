import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import 'coach_check_builder_view.dart';
import 'coach_check_detail_view.dart';
import 'coach_check_templates_view.dart';

/// Check tab root — port of iOS `CoachChecksView`: pending/all review feed +
/// template library entry.
class CoachChecksView extends ConsumerStatefulWidget {
  const CoachChecksView({super.key});

  @override
  ConsumerState<CoachChecksView> createState() => _CoachChecksViewState();
}

class _CoachChecksViewState extends ConsumerState<CoachChecksView> {
  CoachChecksResponse? _res;
  bool _error = false;
  bool _loadingMore = false;
  String _filter = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res =
          await ref.read(apiClientProvider).coachChecks(filter: _filter);
      if (mounted) setState(() => _res = res);
    } catch (_) {
      if (mounted && _res == null) setState(() => _error = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _res == null) return;
    setState(() => _loadingMore = true);
    try {
      final more = await ref
          .read(apiClientProvider)
          .coachChecks(filter: _filter, offset: _res!.checks.length);
      if (mounted) {
        setState(() => _res = _res!.copyWith(
            checks: [..._res!.checks, ...more.checks],
            hasMore: more.hasMore));
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    return ScreenScroll(
      onRefresh: _load,
      spacing: Space.element,
      children: [
        const ScreenHeader(eyebrow: 'Revisione check-in', title: 'Check'),
        Row(
          children: [
            for (final (value, label) in const [
              ('pending', 'Da rivedere'),
              ('all', 'Tutti'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Pressable(
                  onTap: () {
                    setState(() {
                      _filter = value;
                      _res = null;
                    });
                    _load();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          _filter == value ? Palette.violet : Palette.void1,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Palette.line),
                    ),
                    child: Text(label,
                        style: Typo.body(
                            13,
                            FontWeight.w600,
                            _filter == value
                                ? Palette.void0
                                : Palette.textMid)),
                  ),
                ),
              ),
          ],
        ),
        if (res == null && !_error)
          const AvatarRowsSkeleton()
        else if (_error)
          EmptyPanel.network(onCta: () {
            setState(() => _error = false);
            _load();
          })
        else if (res!.checks.isEmpty)
          const EmptyPanel(
            icon: Icons.verified_outlined,
            message: 'Nessun check da rivedere. Ottimo lavoro.',
            tint: Palette.lime,
          )
        else ...[
          for (final c in res.checks)
            VoltPanel(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CoachCheckDetailView(checkId: c.id),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  AvatarView(
                    url: c.client?.profileImageUrl,
                    name: c.client?.displayName ?? '?',
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.client?.displayName ?? 'Atleta',
                            style: Typo.body(14.5, FontWeight.w700)),
                        Text(
                          [
                            c.title,
                            if (Formatters.parseDate(c.submittedAt) != null)
                              Formatters.relative(Formatters.parseDate(
                                      c.submittedAt)!
                                  .toLocal()),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Typo.body(
                              12, FontWeight.w400, Palette.textMid),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(c.reviewed ? 'Fatto' : 'Da rivedere',
                      color: c.reviewed ? Palette.lime : Palette.amber),
                ],
              ),
            ),
          if (res.hasMore)
            LoadMoreButton(onTap: _loadMore, loading: _loadingMore),
        ],
        const Eyebrow('Modelli'),
        NavListRow(
          title: 'Libreria modelli check',
          subtitle: 'Preset e modelli personalizzati',
          icon: Icons.dashboard_customize_rounded,
          accent: Palette.violet,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const CoachCheckTemplatesView())),
        ),
        NavListRow(
          title: 'Crea nuovo modello',
          subtitle: 'Composer a blocchi',
          icon: Icons.add_box_rounded,
          accent: Palette.bronze,
          onTap: () => showAppSheet<void>(context,
              builder: (_) => const CoachCheckBuilderView()),
        ),
      ],
    );
  }
}
