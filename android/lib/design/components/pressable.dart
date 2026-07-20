import 'package:flutter/material.dart';

import '../../core/utils/haptics.dart';
import '../theme.dart';

/// Press-scale wrapper — the brand's universal tap feedback (iOS
/// `PressableButtonStyle`): scale to 0.97 with a snappy spring, no ripple.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = true,
    this.enabled = true,
    this.dim = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  final bool enabled;

  /// Also dim slightly while pressed (iOS `NeonPressStyle` for filled CTAs).
  final bool dim;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedScale(
      scale: _down ? 0.97 : 1,
      duration: Motion.snappyDuration,
      curve: Motion.snappy,
      child: widget.dim
          ? AnimatedOpacity(
              opacity: _down ? 0.9 : 1,
              duration: Motion.snappyDuration,
              child: widget.child,
            )
          : widget.child,
    );
    if (!widget.enabled || (widget.onTap == null && widget.onLongPress == null)) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        if (widget.haptic) Haptics.tap();
        widget.onTap?.call();
      },
      onLongPress: widget.onLongPress,
      child: child,
    );
  }
}

/// Staggered entrance — port of the iOS `revealUp(appear:index:)` modifier,
/// the app's single most-used animation: opacity 0→1, y 26→0, delayed by
/// `index × 0.07 s`.
///
/// iOS also blurs 6→0 here. That is deliberately **not** ported: an
/// `ImageFilter.blur` is an offscreen render target plus a two-pass
/// convolution, per widget per frame, and this widget wraps nearly every card
/// in the app — a list of ten reveals costs ten offscreen passes a frame. The
/// slide + fade reads the same at sigma ≤ 3.
class RevealUp extends StatefulWidget {
  const RevealUp({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<RevealUp> createState() => _RevealUpState();
}

class _RevealUpState extends State<RevealUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.revealDuration,
  );
  late final CurvedAnimation _a =
      CurvedAnimation(parent: _c, curve: Motion.reveal);

  @override
  void initState() {
    super.initState();
    Future.delayed(
      Duration(milliseconds: (widget.index * Motion.staggerStep * 1000).round()),
      () {
        if (mounted) _c.forward();
      },
    );
  }

  @override
  void dispose() {
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) {
        final v = _a.value;
        // Settled: drop the Transform/Opacity wrappers entirely so the
        // steady state costs nothing.
        if (v >= 1) return child!;
        return Transform.translate(
          offset: Offset(0, 26 * (1 - v)),
          child: Opacity(opacity: v, child: child),
        );
      },
      child: widget.child,
    );
  }
}
