import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Chiron centaur mascot — port of iOS `ChironMascot`. The custom
/// "ChironCentaur" illustration was never added to the project (true on iOS
/// too), so this renders the same generated fallback: a bronze→gold gradient
/// seal with an archer icon, idle aura pulse + rotating dashed ring + bob,
/// and a "pop" bounce when [speak] increments.
class ChironMascot extends StatefulWidget {
  const ChironMascot({super.key, this.size = 120, this.speak = 0});

  final double size;
  final int speak;

  @override
  State<ChironMascot> createState() => _ChironMascotState();
}

class _ChironMascotState extends State<ChironMascot>
    with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: Motion.snappyDuration,
    lowerBound: 0,
    upperBound: 1,
  );

  @override
  void didUpdateWidget(ChironMascot old) {
    super.didUpdateWidget(old);
    if (widget.speak != old.speak) {
      _pop.forward(from: 0).then((_) => _pop.reverse());
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion && _idle.isAnimating) _idle.stop();

    return AnimatedBuilder(
      animation: Listenable.merge([_idle, _pop]),
      builder: (context, _) {
        final t = _idle.value * 2 * math.pi;
        final bob = reduceMotion ? 0.0 : math.sin(t) * 4;
        final aura = reduceMotion ? 0.5 : (0.5 + 0.5 * math.sin(t * 1.3));
        final popScale = 1 + 0.08 * Curves.easeOut.transform(_pop.value);
        return Transform.translate(
          offset: Offset(0, bob),
          child: Transform.scale(
            scale: popScale,
            child: SizedBox(
              width: widget.size * 1.35,
              height: widget.size * 1.35,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Aura pulse.
                  Container(
                    width: widget.size * (1.12 + 0.1 * aura),
                    height: widget.size * (1.12 + 0.1 * aura),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Palette.gold
                          .withValues(alpha: 0.10 + 0.08 * aura),
                    ),
                  ),
                  // Rotating dashed ring.
                  Transform.rotate(
                    angle: reduceMotion ? 0 : t * 0.35,
                    child: CustomPaint(
                      size: Size.square(widget.size * 1.24),
                      painter: _DashedRingPainter(),
                    ),
                  ),
                  // Bronze seal + archer.
                  Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFC9971E), Color(0xFF8A6508)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Palette.amber.withValues(alpha: 0.35),
                          blurRadius: 26,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.5),
                    ),
                    child: Icon(Icons.sports_martial_arts_rounded,
                        size: widget.size * 0.45, color: Palette.void0),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Palette.amber.withValues(alpha: 0.55);
    final radius = size.width / 2 - 1;
    final center = size.center(Offset.zero);
    const dashes = 26;
    for (var i = 0; i < dashes; i++) {
      final a0 = i / dashes * 2 * math.pi;
      final a1 = a0 + (2 * math.pi / dashes) * 0.55;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), a0,
          a1 - a0, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
