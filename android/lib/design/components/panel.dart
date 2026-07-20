import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// The near-universal card container (iOS `voltPanel`): marble fill, hairline
/// stroke (optionally tinted), soft ink shadow, continuous corners.
class VoltPanel extends StatelessWidget {
  const VoltPanel({
    super.key,
    required this.child,
    this.tint,
    this.radius = Radii.card,
    this.padding = const EdgeInsets.all(Space.card),
    this.fill = Palette.void1,
    this.onTap,
  });

  final Widget child;
  final Color? tint;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      decoration: voltPanel(tint: tint, radius: radius, fill: fill),
      padding: padding,
      child: child,
    );
    if (onTap == null) return panel;
    return Pressable(onTap: onTap, child: panel);
  }
}

/// Small uppercase mono eyebrow (iOS `voltEyebrow`).
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = Palette.goldText});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: Typo.eyebrow(color: color));
  }
}
