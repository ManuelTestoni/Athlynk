import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// App-wide animated backdrop — port of iOS `VoltBackground`.
///
/// Parchment base + slow figure-eight drift of layered radial washes (marble
/// light top, primary warmth lower-left, second accent upper-right, gold
/// glimmer corner) + a static paper-grain texture. Each screen passes its own
/// 3–4 color [palette]. Freezes to a static wash under reduced motion.
///
/// The drift is a pure translation, so the washes and the grain are painted
/// **once** into a cached raster layer (the [RepaintBoundary] below) that is
/// oversized by the drift amplitude; each frame only moves that layer with a
/// [Transform]. Nothing is re-rasterized per frame — this matters because the
/// backdrop is full-screen on ~16 screens, and the grain alone is 1100 draw
/// calls.
class VoltBackground extends StatefulWidget {
  const VoltBackground({super.key, required this.palette});

  final List<Color> palette;

  @override
  State<VoltBackground> createState() => _VoltBackgroundState();
}

/// Drift amplitude, in fractions of the viewport — also the overscan the
/// cached layer needs on each side so the edges never show.
const _driftX = 0.06;
const _driftY = 0.04;

class _VoltBackgroundState extends State<VoltBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  );

  @override
  void initState() {
    super.initState();
    _t.repeat();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion && _t.isAnimating) _t.stop();

    final a = widget.palette.isNotEmpty ? widget.palette[0] : Palette.magenta;
    final b = widget.palette.length > 1 ? widget.palette[1] : Palette.cyan;

    // Repaints only when the palette changes; cached as a layer in between.
    final Widget layer = RepaintBoundary(
      child: CustomPaint(painter: _WashPainter(a: a, b: b), size: Size.infinite),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(color: Palette.void0),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            if (!w.isFinite || !h.isFinite) return layer;

            return AnimatedBuilder(
              animation: _t,
              // Built once — the builder below only re-reads the offset.
              child: OverflowBox(
                maxWidth: w * (1 + 2 * _driftX),
                maxHeight: h * (1 + 2 * _driftY),
                child: layer,
              ),
              builder: (context, child) {
                final ph = _t.value * 2 * math.pi;
                return Transform.translate(
                  offset: Offset(
                    math.sin(ph) * _driftX * w,
                    math.sin(2 * ph) * _driftY * h,
                  ),
                  child: child,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _WashPainter extends CustomPainter {
  _WashPainter({required this.a, required this.b});

  final Color a;
  final Color b;

  static final _grain = _GrainSpec.generate();

  @override
  void paint(Canvas canvas, Size size) {
    void wash(Offset centerFrac, double radius, Color color,
        {BlendMode blend = BlendMode.srcOver}) {
      final center = Offset(
        centerFrac.dx * size.width,
        centerFrac.dy * size.height,
      );
      final paint = Paint()
        ..blendMode = blend
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    // Marble light, top.
    wash(const Offset(0.6, -0.1), 520, Colors.white.withValues(alpha: 0.55));
    // Primary warmth, lower-left.
    wash(const Offset(0.06, 0.85), 420, a.withValues(alpha: 0.07));
    // Second accent, upper-right.
    wash(const Offset(0.95, 0.12), 420, b.withValues(alpha: 0.055));
    // Gold glimmer corner.
    wash(const Offset(0.92, 0.92), 260, Palette.gold.withValues(alpha: 0.045),
        blend: BlendMode.plus);

    // Static paper grain.
    final grainPaint = Paint()
      ..color = Palette.textHi.withValues(alpha: 0.025)
      ..blendMode = BlendMode.multiply;
    for (final dot in _grain) {
      canvas.drawCircle(
        Offset(dot.$1 * size.width, dot.$2 * size.height),
        dot.$3,
        grainPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WashPainter old) => old.a != a || old.b != b;
}

class _GrainSpec {
  /// 1100 random dots, generated once (deterministic seed → stable texture).
  static List<(double, double, double)> generate() {
    final rnd = math.Random(7);
    return List.generate(
      1100,
      (_) => (rnd.nextDouble(), rnd.nextDouble(), rnd.nextDouble() * 0.9 + 0.3),
    );
  }
}
