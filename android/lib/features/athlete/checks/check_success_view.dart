import 'package:flutter/material.dart';

import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/particle_burst.dart';
import '../../../design/components/volt_background.dart';
import '../../../design/theme.dart';

/// Confirmation after submitting a check — port of iOS `CheckSuccessView`:
/// animated bronze seal + checkmark + confetti.
class CheckSuccessView extends StatefulWidget {
  const CheckSuccessView({super.key, required this.title});

  final String title;

  @override
  State<CheckSuccessView> createState() => _CheckSuccessViewState();
}

class _CheckSuccessViewState extends State<CheckSuccessView> {
  int _burst = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _burst = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const VoltBackground(palette: [Palette.violet, Palette.amber]),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                children: [
                  const Spacer(),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ParticleBurst(trigger: _burst),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.5, end: 1),
                        duration: Motion.luxeDuration,
                        curve: Motion.luxe,
                        builder: (context, v, child) =>
                            Transform.scale(scale: v, child: child),
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFC9971E), Color(0xFF8A6508)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    Palette.amber.withValues(alpha: 0.4),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 52, color: Palette.void0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  const Eyebrow('Check inviato'),
                  const SizedBox(height: 8),
                  Text('Check compilato con successo',
                      textAlign: TextAlign.center, style: Typo.poster(32)),
                  const SizedBox(height: 10),
                  Text(
                    '"${widget.title}" è stato inviato al tuo coach.',
                    textAlign: TextAlign.center,
                    style: Typo.body(14.5, FontWeight.w400, Palette.textMid),
                  ),
                  const Spacer(),
                  NeonButton(
                    'Torna ai check',
                    color: Palette.violet,
                    onTap: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
