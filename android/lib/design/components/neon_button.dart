import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// Pill CTA — port of iOS `NeonButton`.
/// `filled`: solid color fill, white text. Ghost: colored text + border +
/// 7%-opacity wash. Optional leading icon and loading spinner swap.
class NeonButton extends StatelessWidget {
  const NeonButton(
    this.label, {
    super.key,
    this.onTap,
    this.color,
    this.filled = true,
    this.icon,
    this.loading = false,
    this.compact = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool filled;
  final IconData? icon;
  final bool loading;
  final bool compact;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Palette.magenta;
    final fg = filled ? Palette.void0 : c;
    final height = compact ? 44.0 : 54.0;

    final content = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: compact ? 16 : 18, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Typo.body(compact ? 14 : 16, FontWeight.w700, fg),
                ),
              ),
            ],
          );

    return Pressable(
      onTap: (loading || onTap == null) ? null : onTap,
      dim: filled,
      child: AnimatedContainer(
        duration: Motion.snappyDuration,
        height: height,
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24),
        decoration: BoxDecoration(
          color: filled ? c : c.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(height / 2),
          border: filled ? null : Border.all(color: c.withValues(alpha: 0.55)),
          boxShadow: filled ? neonGlow(c) : null,
        ),
        child: Center(child: content),
      ),
    );
  }
}
