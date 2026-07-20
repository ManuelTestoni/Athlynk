import 'package:flutter/material.dart';

import '../../core/utils/haptics.dart';
import '../../design/components/chiron_mascot.dart';
import '../../design/components/neon_button.dart';
import '../../design/components/particle_burst.dart';
import '../../design/components/volt_background.dart';
import '../../design/theme.dart';

class OnboardingSlide {
  const OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
    this.mascot = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool mascot;
}

/// First-launch paged marketing intro (6 slides) — port of iOS
/// `OnboardingView` / `CoachOnboardingView`. Skippable, not account-linked.
class OnboardingView extends StatefulWidget {
  const OnboardingView({
    super.key,
    required this.slides,
    required this.onDone,
  });

  final List<OnboardingSlide> slides;
  final VoidCallback onDone;

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final _controller = PageController();
  int _page = 0;
  int _burst = 0;

  bool get _last => _page == widget.slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _advance() {
    if (_last) {
      setState(() => _burst++);
      Future.delayed(const Duration(milliseconds: 350), widget.onDone);
    } else {
      Haptics.tap();
      _controller.nextPage(
          duration: Motion.pageEnterDuration, curve: Motion.pageEnter);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const VoltBackground(palette: [
            Palette.defaultPrimary,
            Palette.violet,
            Palette.defaultAccent,
            Palette.defaultPrimary,
          ]),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.onDone,
                    child: Text('Salta',
                        style:
                            Typo.body(14, FontWeight.w600, Palette.textLow)),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: widget.slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) {
                      final slide = widget.slides[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 34),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (slide.mascot)
                              const ChironMascot(size: 110)
                            else
                              Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      Palette.amber.withValues(alpha: 0.1),
                                  border: Border.all(
                                      color: Palette.amber
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Icon(slide.icon,
                                    size: 40, color: Palette.amber),
                              ),
                            const SizedBox(height: 34),
                            Text(slide.title,
                                textAlign: TextAlign.center,
                                style: Typo.poster(34)),
                            const SizedBox(height: 14),
                            Text(
                              slide.body,
                              textAlign: TextAlign.center,
                              style: Typo.body(
                                  15, FontWeight.w400, Palette.textMid),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.slides.length; i++)
                      AnimatedContainer(
                        duration: Motion.snappyDuration,
                        curve: Motion.snappy,
                        margin: const EdgeInsets.symmetric(horizontal: 3.5),
                        width: i == _page ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? Palette.amber
                              : Palette.void2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ParticleBurst(trigger: _burst),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Space.screenH),
                      child: NeonButton(
                        _last ? 'Inizia' : 'Avanti',
                        onTap: _advance,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
