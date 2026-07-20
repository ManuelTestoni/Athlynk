import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated circular progress ring with angular-gradient stroke and a glowing
/// leading dot (iOS `RingGauge`). Used for session completion %, calorie
/// ring, review-rate ring.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.progress,
    this.size = 120,
    this.stroke = 10,
    this.color,
    this.center,
  });

  /// 0–1 (values > 1 clamp; "over" states recolor at the call site).
  final double progress;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Palette.cyan;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: Motion.luxeDuration,
      curve: Motion.luxe,
      builder: (context, value, _) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: _RingPainter(value: value, color: c, stroke: stroke),
              ),
              ?center,
            ],
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.stroke});

  final double value;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Palette.void2;
    canvas.drawCircle(center, radius, track);

    if (value <= 0) return;

    const start = -math.pi / 2;
    final sweep = 2 * math.pi * value;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        transform: const GradientRotation(start),
        colors: [color.withValues(alpha: 0.45), color],
        stops: const [0, 1],
      ).createShader(rect);
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius), start, sweep, false, arc);

    // Glowing leading dot.
    final angle = start + sweep;
    final dot = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas.drawCircle(
      dot,
      stroke * 0.68,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(dot, stroke * 0.42, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.stroke != stroke;
}
