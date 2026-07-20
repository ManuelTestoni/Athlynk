import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../design/components/misc.dart';
import '../../design/components/neon_button.dart';
import '../../design/components/volt_background.dart';
import '../../design/theme.dart';

/// Cold-open brand splash — port of iOS `SplashView`/`CoachSplashView`.
/// Runs `bootstrap()` once; shows a retry affordance when the boot failed for
/// a non-401 reason (offline/5xx) instead of kicking the user to login.
class SplashView extends ConsumerStatefulWidget {
  const SplashView({
    super.key,
    required this.title,
    this.subtitle,
    this.tagline,
    required this.palette,
  });

  final String title;
  final String? subtitle;
  final String? tagline;
  final List<Color> palette;

  @override
  ConsumerState<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends ConsumerState<SplashView> {
  @override
  void initState() {
    super.initState();
    // Small brand beat before booting (iOS waits ~1.2 s on the coach splash).
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        ref.read(sessionControllerProvider.notifier).bootstrap();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final retryable = ref.watch(
        sessionControllerProvider.select((s) => s.bootstrapRetryable));

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          VoltBackground(palette: widget.palette),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                const Icon(Icons.account_balance_rounded,
                    size: 44, color: Palette.amber),
                const SizedBox(height: 18),
                GlitchText(widget.title),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.subtitle!.toUpperCase(),
                    style: Typo.mono(13, FontWeight.w700, Palette.textMid)
                        .copyWith(letterSpacing: 6),
                  ),
                ],
                if (widget.tagline != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    widget.tagline!,
                    style: Typo.mono(10, FontWeight.w600, Palette.goldText)
                        .copyWith(letterSpacing: 3),
                  ),
                ],
                const Spacer(flex: 2),
                if (retryable)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 60, vertical: 8),
                    child: Column(
                      children: [
                        Text(S.errOffline,
                            style: Typo.body(
                                14, FontWeight.w500, Palette.textMid)),
                        const SizedBox(height: 12),
                        NeonButton(
                          S.retry,
                          compact: true,
                          onTap: () => ref
                              .read(sessionControllerProvider.notifier)
                              .bootstrap(),
                        ),
                      ],
                    ),
                  )
                else
                  const _ChargeBar(),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin indeterminate charge bar under the wordmark.
class _ChargeBar extends StatefulWidget {
  const _ChargeBar();

  @override
  State<_ChargeBar> createState() => _ChargeBarState();
}

class _ChargeBarState extends State<_ChargeBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Stack(
              children: [
                Container(color: Palette.void2),
                FractionallySizedBox(
                  widthFactor: 0.4,
                  alignment: Alignment(-1 + 2.8 * _c.value, 0),
                  child: Container(color: Palette.amber),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
