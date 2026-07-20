import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/utils/haptics.dart';
import '../theme.dart';

/// One-shot 26-particle confetti burst (iOS `ParticleBurst`): random
/// angle/distance(80–190)/size/color/spin, easeOut 0.9 s, success haptic.
/// Fire by incrementing [trigger].
class ParticleBurst extends StatefulWidget {
  const ParticleBurst({super.key, required this.trigger, this.colors});

  final int trigger;
  final List<Color>? colors;

  @override
  State<ParticleBurst> createState() => _ParticleBurstState();
}

class _Particle {
  _Particle(math.Random rnd, List<Color> colors)
      : angle = rnd.nextDouble() * 2 * math.pi,
        distance = 80 + rnd.nextDouble() * 110,
        size = 4 + rnd.nextDouble() * 6,
        spin = (rnd.nextDouble() - 0.5) * 6,
        color = colors[rnd.nextInt(colors.length)];

  final double angle;
  final double distance;
  final double size;
  final double spin;
  final Color color;
}

class _ParticleBurstState extends State<ParticleBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  List<_Particle> _particles = const [];

  static const _defaultColors = [
    Palette.defaultPrimary,
    Palette.defaultAccent,
    Palette.lime,
    Palette.amber,
    Palette.gold,
  ];

  @override
  void didUpdateWidget(ParticleBurst old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger > 0) _fire();
  }

  void _fire() {
    if (MediaQuery.of(context).disableAnimations) return;
    final rnd = math.Random();
    _particles = List.generate(
        26, (_) => _Particle(rnd, widget.colors ?? _defaultColors));
    Haptics.success();
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          if (_c.value == 0 || _c.isDismissed) return const SizedBox.shrink();
          return CustomPaint(
            size: const Size(260, 260),
            painter: _BurstPainter(
              particles: _particles,
              t: Curves.easeOut.transform(_c.value),
            ),
          );
        },
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.particles, required this.t});

  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final opacity = (1 - t).clamp(0.0, 1.0);
    for (final p in particles) {
      final d = p.distance * t;
      final pos = center + Offset(math.cos(p.angle), math.sin(p.angle)) * d;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t);
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.7),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
