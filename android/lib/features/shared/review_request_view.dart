import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../design/components/chiron_mascot.dart';
import '../../design/components/neon_button.dart';
import '../../design/components/particle_burst.dart';
import '../../design/components/volt_background.dart';
import '../../design/theme.dart';

/// Post-tutorial store-review prompt — port of iOS `ReviewRequestView`
/// (SKStoreReviewController → Play Store listing on Android). Shown once
/// ever, gated by the `athlynk.reviewDone` pref.
class ReviewRequestView extends ConsumerStatefulWidget {
  const ReviewRequestView({super.key});

  @override
  ConsumerState<ReviewRequestView> createState() => _ReviewRequestViewState();
}

class _ReviewRequestViewState extends ConsumerState<ReviewRequestView> {
  int _burst = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _burst = 1);
    });
  }

  Future<void> _review() async {
    final flavor = ref.read(flavorProvider);
    final uri = Uri.parse(
        'https://play.google.com/store/apps/details?id=${flavor.bundleId}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted) {
      ref.read(sessionControllerProvider.notifier).dismissReview();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const VoltBackground(
              palette: [Palette.amber, Palette.defaultPrimary]),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                children: [
                  const Spacer(),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ParticleBurst(trigger: _burst),
                      const ChironMascot(size: 120),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Text('Ti piace Athlynk?',
                      textAlign: TextAlign.center, style: Typo.poster(36)),
                  const SizedBox(height: 12),
                  Text(
                    'Una recensione aiuta altri atleti e coach a scoprire la piattaforma.',
                    textAlign: TextAlign.center,
                    style: Typo.body(15, FontWeight.w400, Palette.textMid),
                  ),
                  const Spacer(),
                  NeonButton('Lascia una recensione', onTap: _review),
                  const SizedBox(height: 10),
                  NeonButton(
                    'Non ora',
                    filled: false,
                    color: Palette.textMid,
                    onTap: () => ref
                        .read(sessionControllerProvider.notifier)
                        .dismissReview(),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
