import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';

/// "Integratori" — port of iOS `SupplementsView`: protocol sheets with item
/// cards (dose + timing + notes), 10 per page.
class SupplementsView extends ConsumerStatefulWidget {
  const SupplementsView({super.key});

  @override
  ConsumerState<SupplementsView> createState() => _SupplementsViewState();
}

class _SupplementsViewState extends ConsumerState<SupplementsView> {
  List<SupplementSheetDto>? _sheets;
  bool _error = false;
  bool _hasMore = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).supplements();
      if (mounted) {
        setState(() {
          _sheets = res.sheets;
          _hasMore = res.hasMore;
        });
      }
    } catch (_) {
      if (mounted && _sheets == null) setState(() => _error = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await ref
          .read(apiClientProvider)
          .supplements(offset: _sheets?.length ?? 0);
      if (mounted) {
        setState(() {
          _sheets = [...?_sheets, ...res.sheets];
          _hasMore = res.hasMore;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheets = _sheets;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Protocollo', title: 'Integratori'),
          if (sheets == null && !_error)
            const ListCardsSkeleton(count: 2, height: 170)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (sheets!.isEmpty)
            const EmptyPanel(
              icon: Icons.medication_outlined,
              message:
                  'Non hai ancora un protocollo di integrazione assegnato.',
            )
          else ...[
            for (final sheet in sheets) _sheetCard(sheet),
            if (_hasMore)
              LoadMoreButton(onTap: _loadMore, loading: _loadingMore),
          ],
        ],
      ),
    );
  }

  Widget _sheetCard(SupplementSheetDto sheet) {
    return VoltPanel(
      tint: Palette.lime.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sheet.title, style: Typo.display(19)),
          if (sheet.coach != null)
            Text('di ${sheet.coach!.fullName}',
                style: Typo.body(12.5, FontWeight.w400, Palette.textMid)),
          if ((sheet.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(sheet.notes!,
                style: Typo.body(13, FontWeight.w400, Palette.textMid)),
          ],
          const SizedBox(height: 12),
          for (final item in sheet.items)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Palette.void0,
                borderRadius: BorderRadius.circular(Radii.chip),
                border: Border.all(color: Palette.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medication_rounded,
                      size: 18, color: Palette.lime),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: Typo.body(14.5, FontWeight.w700)),
                        if ((item.notes ?? '').isNotEmpty)
                          Text(item.notes!,
                              style: Typo.body(
                                  12, FontWeight.w400, Palette.textMid)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (item.dose.isNotEmpty)
                        Text(item.dose,
                            style:
                                Typo.mono(12, FontWeight.w700, Palette.lime)),
                      if ((item.timing ?? '').isNotEmpty)
                        Text(item.timing!,
                            style: Typo.mono(
                                9, FontWeight.w600, Palette.textLow)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
