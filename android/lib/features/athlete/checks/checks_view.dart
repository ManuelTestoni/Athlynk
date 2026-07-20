import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/push/push_bridge.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import '../progress/progress_tracker_view.dart';
import 'new_check_view.dart';

/// Check tab root — port of iOS `ChecksView`: pending check-in timeline
/// (colored node rail) + progress link. "Nuovo Check" stays a placeholder,
/// exactly like iOS (no create endpoint exists yet).
class ChecksView extends ConsumerStatefulWidget {
  const ChecksView({super.key});

  @override
  ConsumerState<ChecksView> createState() => _ChecksViewState();
}

class _ChecksViewState extends ConsumerState<ChecksView> {
  List<CheckDto>? _checks;
  bool _error = false;
  StreamSubscription<String>? _remote;

  @override
  void initState() {
    super.initState();
    _load();
    _remote = ref.read(pushBridgeProvider).onTypes({
      RemoteChangeType.checkReviewed,
      RemoteChangeType.checkSubmitted,
    }).listen((_) => _load());
  }

  @override
  void dispose() {
    _remote?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final checks = await ref.read(apiClientProvider).checks();
      if (mounted) {
        setState(() {
          _checks = checks;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted && _checks == null) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checks = _checks;
    return ScreenScroll(
      onRefresh: _load,
      spacing: Space.element,
      children: [
        const ScreenHeader(eyebrow: 'Check-in', title: 'Check'),
        if (checks == null && !_error)
          const TimelineSkeleton()
        else if (_error)
          EmptyPanel.network(onCta: () {
            setState(() => _error = false);
            _load();
          })
        else if (checks!.isEmpty)
          const EmptyPanel(
            icon: Icons.verified_outlined,
            message: 'Tutto in regola. Nessun check-in da compilare.',
            tint: Palette.lime,
          )
        else
          for (final (i, check) in checks.indexed)
            RevealUp(index: i, child: _checkRow(check, i)),
        NavListRow(
          title: 'Andamento progressi',
          subtitle: 'Peso, misure e foto nel tempo',
          icon: Icons.query_stats_rounded,
          accent: Palette.violet,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const ProgressTrackerView())),
        ),
      ],
    );
  }

  Widget _checkRow(CheckDto check, int index) {
    final accent = Palette.accent(index);
    final due = Formatters.parseDate(check.dueDate);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 18),
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                border: Border.all(color: Palette.void0, width: 2),
                boxShadow: neonGlow(accent),
              ),
            ),
            Container(
              width: 2,
              height: 56,
              color: Palette.line,
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: VoltPanel(
            tint: accent.withValues(alpha: 0.35),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => NewCheckView(check: check))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        due == null
                            ? 'Da compilare'
                            : Formatters.mediumDate(due),
                        style: Typo.mono(
                            10, FontWeight.w600, Palette.textLow),
                      ),
                    ),
                    const StatusBadge('Da compilare', color: Palette.amber),
                  ],
                ),
                const SizedBox(height: 6),
                Text(check.title, style: Typo.display(18)),
                if (check.coach != null)
                  Text('di ${check.coach!.fullName}',
                      style: Typo.body(
                          12.5, FontWeight.w400, Palette.textMid)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
