import 'package:flutter/material.dart';

import '../../core/utils/haptics.dart';
import '../theme.dart';
import 'particle_burst.dart';

/// Full-screen success/failure seal flash (iOS `StatusOverlay`): animated
/// colored seal + icon + message, confetti on success, auto-dismiss 1.6 s.
///
/// Usage: `StatusFlash.show(context, success: true, message: 'Salvato')`.
class StatusFlash {
  StatusFlash._();

  static Future<void> show(
    BuildContext context, {
    required bool success,
    required String message,
  }) async {
    if (success) {
      Haptics.success();
    } else {
      Haptics.error();
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _StatusFlashView(success: success, message: message),
    );
    overlay.insert(entry);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    entry.remove();
  }
}

class _StatusFlashView extends StatefulWidget {
  const _StatusFlashView({required this.success, required this.message});

  final bool success;
  final String message;

  @override
  State<_StatusFlashView> createState() => _StatusFlashViewState();
}

class _StatusFlashViewState extends State<_StatusFlashView> {
  int _burst = 0;

  @override
  void initState() {
    super.initState();
    if (widget.success) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _burst = 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.success ? Palette.lime : Palette.crimson;
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Palette.textHi.withValues(alpha: 0.18),
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ParticleBurst(trigger: _burst),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: Motion.snappyDuration,
                curve: Motion.snappy,
                builder: (context, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  padding: const EdgeInsets.all(26),
                  decoration: voltPanel(radius: Radii.hero),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.14),
                          border:
                              Border.all(color: color.withValues(alpha: 0.5)),
                        ),
                        child: Icon(
                          widget.success
                              ? Icons.verified_rounded
                              : Icons.error_outline_rounded,
                          size: 30,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(widget.message,
                          textAlign: TextAlign.center,
                          style: Typo.display(17)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
