import 'package:flutter/material.dart';

import '../theme.dart';
import 'neon_button.dart';

/// Async confirm/alert overlay — port of iOS `ConfirmCenter` /
/// `ConfirmDialogCard`, the app-wide replacement for system alerts.
///
/// `await ConfirmCenter.confirm(context, ConfirmOptions(...))` resolves true
/// on confirm, false on cancel/dismiss.
enum ConfirmVariant { danger, neutral }

class ConfirmOptions {
  const ConfirmOptions({
    required this.title,
    this.subtitle,
    this.icon,
    this.variant = ConfirmVariant.neutral,
    this.confirmLabel = 'Conferma',
    this.cancelLabel = 'Annulla',
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final ConfirmVariant variant;
  final String confirmLabel;
  final String cancelLabel;
}

class ConfirmCenter {
  ConfirmCenter._();

  static Future<bool> confirm(
      BuildContext context, ConfirmOptions options) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'conferma',
      barrierColor: Palette.textHi.withValues(alpha: 0.3),
      transitionDuration: Motion.snappyDuration,
      transitionBuilder: (context, anim, _, child) {
        final v = Motion.snappy.transform(anim.value);
        return Transform.scale(
          scale: 0.92 + 0.08 * v,
          child: Opacity(opacity: anim.value.clamp(0, 1), child: child),
        );
      },
      pageBuilder: (context, _, _) => Center(
        child: _ConfirmCard(options: options),
      ),
    );
    return result ?? false;
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.options});

  final ConfirmOptions options;

  @override
  Widget build(BuildContext context) {
    final accent = options.variant == ConfirmVariant.danger
        ? Palette.crimson
        : Palette.cyan;
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 34),
        padding: const EdgeInsets.all(24),
        decoration: voltPanel(radius: Radii.hero),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (options.icon != null) ...[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                ),
                child: Icon(options.icon, size: 24, color: accent),
              ),
              const SizedBox(height: 14),
            ],
            Text(options.title,
                textAlign: TextAlign.center, style: Typo.display(19)),
            if (options.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                options.subtitle!,
                textAlign: TextAlign.center,
                style: Typo.body(14, FontWeight.w400, Palette.textMid),
              ),
            ],
            const SizedBox(height: 22),
            NeonButton(
              options.confirmLabel,
              color: accent,
              compact: true,
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 10),
            NeonButton(
              options.cancelLabel,
              color: Palette.textMid,
              filled: false,
              compact: true,
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
