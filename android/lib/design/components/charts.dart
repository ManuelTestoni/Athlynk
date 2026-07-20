import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/utils/haptics.dart';
import '../theme.dart';

/// Minimal line+fill sparkline with end dot (iOS `SparklineView`).
class SparklineView extends StatelessWidget {
  const SparklineView({
    super.key,
    required this.values,
    this.color,
    this.height = 46,
  });

  final List<double> values;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter:
            _SparklinePainter(values: values, color: color ?? Palette.cyan),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final span = (max - min).abs() < 1e-9 ? 1.0 : max - min;

    Offset point(int i) => Offset(
          i / (values.length - 1) * size.width,
          size.height - ((values[i] - min) / span) * (size.height - 6) - 3,
        );

    final line = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(point(i).dx, point(i).dy);
    }

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    final last = point(values.length - 1);
    canvas.drawCircle(last, 3.4, Paint()..color = color);
    canvas.drawCircle(last, 1.8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

/// One data point of a scrubbabile trend chart.
class TrendPoint {
  const TrendPoint({required this.value, required this.label, this.raw});

  final double value;

  /// Tooltip label (usually a date).
  final String label;

  /// Optional secondary tooltip line.
  final String? raw;
}

/// Drag-to-scrub line+area chart with gridlines, Y labels and a snapping
/// tooltip — port of the iOS `TrendLine`/`TrendChart` family. Haptic tick on
/// index change.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.points,
    this.color,
    this.height = 180,
    this.unit = '',
    this.dots = const [],
  });

  final List<TrendPoint> points;
  final Color? color;
  final double height;
  final String unit;

  /// Faint raw-sample dots behind the mean line (weekly-mean charts).
  final List<Offset> dots;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _scrubIndex;

  void _updateScrub(Offset local, Size size) {
    if (widget.points.length < 2) return;
    final t = (local.dx / size.width).clamp(0.0, 1.0);
    final idx = (t * (widget.points.length - 1)).round();
    if (idx != _scrubIndex) {
      Haptics.soft();
      setState(() => _scrubIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text('Dati insufficienti per il grafico.',
              style: Typo.body(13, FontWeight.w400, Palette.textLow)),
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, widget.height);
          return GestureDetector(
            onPanDown: (d) => _updateScrub(d.localPosition, size),
            onPanUpdate: (d) => _updateScrub(d.localPosition, size),
            onPanEnd: (_) => setState(() => _scrubIndex = null),
            onPanCancel: () => setState(() => _scrubIndex = null),
            child: CustomPaint(
              size: size,
              painter: _TrendChartPainter(
                points: widget.points,
                color: widget.color ?? Palette.cyan,
                scrubIndex: _scrubIndex,
                unit: widget.unit,
                dots: widget.dots,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.points,
    required this.color,
    required this.scrubIndex,
    required this.unit,
    required this.dots,
  });

  final List<TrendPoint> points;
  final Color color;
  final int? scrubIndex;
  final String unit;
  final List<Offset> dots;

  static const _leftPad = 34.0;
  static const _topPad = 10.0;
  static const _bottomPad = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.map((p) => p.value).toList();
    var min = values.reduce(math.min);
    var max = values.reduce(math.max);
    if ((max - min).abs() < 1e-9) {
      min -= 1;
      max += 1;
    }
    final chartW = size.width - _leftPad;
    final chartH = size.height - _topPad - _bottomPad;

    Offset pt(int i) => Offset(
          _leftPad + i / (points.length - 1) * chartW,
          _topPad + (1 - (values[i] - min) / (max - min)) * chartH,
        );

    // Gridlines + Y labels (3 lines).
    final gridPaint = Paint()
      ..color = Palette.line
      ..strokeWidth = 0.7;
    final textStyle = Typo.mono(9, FontWeight.w500, Palette.textLow);
    for (var g = 0; g < 3; g++) {
      final frac = g / 2;
      final y = _topPad + frac * chartH;
      canvas.drawLine(Offset(_leftPad, y), Offset(size.width, y), gridPaint);
      final v = max - frac * (max - min);
      final tp = TextPainter(
        text: TextSpan(text: _fmt(v), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    // Faint raw dots (normalized 0-1 coords in `dots`).
    for (final d in dots) {
      canvas.drawCircle(
        Offset(_leftPad + d.dx * chartW, _topPad + (1 - d.dy) * chartH),
        2,
        Paint()..color = color.withValues(alpha: 0.22),
      );
    }

    // Area + line.
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(_leftPad + chartW, _topPad + chartH)
      ..lineTo(_leftPad, _topPad + chartH)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    // Point markers.
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(pt(i), 3, Paint()..color = color);
      canvas.drawCircle(pt(i), 1.6, Paint()..color = Colors.white);
    }

    // Scrub tooltip.
    final si = scrubIndex;
    if (si != null && si >= 0 && si < points.length) {
      final p = pt(si);
      canvas.drawLine(
        Offset(p.dx, _topPad),
        Offset(p.dx, _topPad + chartH),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 5, Paint()..color = color);
      canvas.drawCircle(p, 2.6, Paint()..color = Colors.white);

      final tip = points[si];
      final valueText = '${_fmt(tip.value)}${unit.isEmpty ? '' : ' $unit'}';
      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(text: '$valueText\n', style: Typo.mono(11, FontWeight.w700)),
          TextSpan(
              text: tip.raw == null ? tip.label : '${tip.label}\n${tip.raw}',
              style: Typo.mono(9, FontWeight.w500, Palette.textLow)),
        ]),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      final w = tp.width + 18;
      final h = tp.height + 12;
      var x = (p.dx - w / 2).clamp(_leftPad, size.width - w);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 0, w, h),
        const Radius.circular(9),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = Palette.void1,
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Palette.line,
      );
      tp.paint(canvas, Offset(x + 9, 6));
    }
  }

  static String _fmt(double v) {
    if (v.abs() >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    return v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(_TrendChartPainter old) =>
      old.points != points || old.scrubIndex != scrubIndex || old.color != color;
}

/// Delta pill: up/down arrow + value, green when favorable (iOS `DeltaPill`).
class DeltaPill extends StatelessWidget {
  const DeltaPill({
    super.key,
    required this.delta,
    this.unit = '',
    this.downIsGood = false,
  });

  final double delta;
  final String unit;
  final bool downIsGood;

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    final good = downIsGood ? !up : up;
    final color = delta == 0
        ? Palette.textLow
        : (good ? Palette.lime : Palette.crimson);
    final arrow = delta == 0
        ? Icons.remove_rounded
        : (up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded);
    final v = delta.abs();
    final label =
        v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(arrow, size: 12, color: color),
          const SizedBox(width: 2),
          Text('$label$unit', style: Typo.mono(11, FontWeight.w700, color)),
        ],
      ),
    );
  }
}

/// Simple bar chart (coach adherence / check-volume charts).
class BarsChart extends StatelessWidget {
  const BarsChart({
    super.key,
    required this.values,
    required this.labels,
    this.color,
    this.height = 140,
    this.maxValue,
  });

  final List<double> values;
  final List<String> labels;
  final Color? color;
  final double height;
  final double? maxValue;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Palette.cyan;
    final max = maxValue ??
        (values.isEmpty ? 1.0 : values.reduce(math.max)).clamp(1e-9, double.infinity);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, v) in values.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    v == v.roundToDouble()
                        ? v.toInt().toString()
                        : v.toStringAsFixed(1),
                    style: Typo.mono(9, FontWeight.w600, Palette.textLow),
                  ),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (v / max).clamp(0.02, 1.0)),
                    duration: Motion.luxeDuration,
                    curve: Motion.luxe,
                    builder: (context, frac, _) => Container(
                      height: frac * (height - 44),
                      decoration: BoxDecoration(
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(6)),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [color.withValues(alpha: 0.55), color],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    i < labels.length ? labels[i] : '',
                    style: Typo.mono(8, FontWeight.w600, Palette.textLow),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
